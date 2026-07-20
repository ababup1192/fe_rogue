// Flix GE Editor ランチャー (Tauri v2)。
//
// 役割はランチャーに徹する (ロジックは editor_server 側):
//   1. 空きポートを選ぶ
//   2. editor_server の実行可能 jar を java で子プロセス起動 (EDITOR_PORT/EDITOR_WEB を渡す)
//   3. /health を 200 が返るまでポーリング
//   4. WebView をその URL に向ける
//   5. アプリ終了時に子プロセス "グループごと" kill (java の残留 = ポート占有を防ぐ)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use tauri::{Manager, RunEvent, WebviewUrl, WebviewWindowBuilder};

// フロントへ返す「見えたゲームプロセスの生情報」1 件。
// 意味づけ (どれがどのプロジェクトか) はしない = cwd をそのまま渡す。
#[derive(serde::Serialize)]
struct RunningGame {
    pid: u32,
    cwd: String,
}

// 走っているゲームの列挙。ゲームの目印は LWJGL/GLFW 必須の起動フラグ
// -XstartOnFirstThread (editor_server は headless なので持たない)。
// プロセス列挙は sysinfo。ただし macOS では sysinfo が他プロセスの引数/cwd を
// 権限不足で読めない (task_for_pid が要る) ので、引数は ps、cwd は lsof に
// フォールバックする。どちらも権限不要で全プロセスを読める外部コマンド。
#[tauri::command]
fn list_running_games() -> Vec<RunningGame> {
    use sysinfo::{ProcessesToUpdate, System};
    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);

    let mut games = Vec::new();
    for (pid, proc_) in sys.processes() {
        let pid = pid.as_u32();
        // sysinfo の引数が空なら ps で取り直す (macOS の権限壁の回避)。
        let cmdline = {
            let joined = proc_
                .cmd()
                .iter()
                .map(|s| s.to_string_lossy())
                .collect::<Vec<_>>()
                .join(" ");
            if joined.is_empty() {
                cmdline_via_ps(pid)
            } else {
                joined
            }
        };
        // ゲームは実ウィンドウを開くので headless を付けない。editor_server は
        // bin/flix 経由だと -XstartOnFirstThread も付くが常に headless なので、
        // headless の有無でゲームと確実に切り分けられる。
        let is_game = cmdline.contains("-XstartOnFirstThread")
            && !cmdline.contains("-Djava.awt.headless=true");
        if !is_game {
            continue;
        }
        // cwd も同様に sysinfo → lsof の順で拾う。
        let cwd = proc_
            .cwd()
            .map(|p| p.to_string_lossy().into_owned())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| cwd_via_lsof(pid));
        games.push(RunningGame { pid, cwd });
    }
    games
}

// sysinfo が引数を取れない時の保険。ps は権限不要で全引数を返す。
fn cmdline_via_ps(pid: u32) -> String {
    Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "command="])
        .env_remove("DEVELOPER_DIR")
        .env_remove("SDKROOT")
        .output()
        .ok()
        .and_then(|out| String::from_utf8(out.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

// sysinfo が cwd を取れない時の保険。lsof の cwd 行の最終列がそれ。
fn cwd_via_lsof(pid: u32) -> String {
    Command::new("lsof")
        .args(["-a", "-d", "cwd", "-p", &pid.to_string(), "-Fn"])
        .env_remove("DEVELOPER_DIR")
        .env_remove("SDKROOT")
        .output()
        .ok()
        .and_then(|out| {
            String::from_utf8(out.stdout).ok().and_then(|text| {
                // -Fn 出力は "n<path>" 行。cwd の実体パスをその接頭辞から取る。
                text.lines()
                    .find_map(|line| line.strip_prefix('n').map(str::to_string))
            })
        })
        .unwrap_or_default()
}

// 起動した java のプロセスグループ ID (= リーダーの pid)。
// シグナルハンドラからも触れるよう atomic のグローバルに置く (0 = 未起動)。
static SERVER_PGID: AtomicI32 = AtomicI32::new(0);

// 開発時 (cargo run = バンドル外) のフォールバックパス。
// .app に固めた時はこれらを使わず、バンドル内リソースから解決する。
const DEV_JAVA: &str = "/Users/abab/Desktop/flix_game_engine/.devbox/nix/profile/default/bin/java";
const DEV_EDITOR_SERVER_JAR: &str =
    "/Users/abab/Desktop/flix_game_engine/editor_server/artifact/editor_server.jar";
const DEV_EDITOR_WEB_DIST: &str = "/Users/abab/Desktop/flix_ge_resource_editor/dist";

// 実行に要る 3 つの在処 (java 実行ファイル・jar・配信 dist)。
struct Assets {
    java: PathBuf,
    jar: PathBuf,
    web: PathBuf,
}

// .app に固めた時のリソース置き場を実行時に解決する。
// バンドルは <App>.app/Contents/MacOS/<bin> に実行ファイル、
// <App>.app/Contents/Resources/ に bundle.resources のファイルが入る。
// AppHandle はまだ無い (health を待ってから WebView を開く設計) ので、
// 実行ファイルの隣から Contents/Resources を自前で辿る。
fn resolve_assets() -> Assets {
    let bundled = std::env::current_exe().ok().and_then(|exe| {
        // exe = .../<App>.app/Contents/MacOS/<bin> → Resources へ
        let resources = exe.parent()?.parent()?.join("Resources");
        let java = resources.join("jre").join("bin").join("java");
        let jar = resources.join("editor_server.jar");
        let web = resources.join("dist");
        // 同梱 JRE が居れば「固めた .app として起動された」と判断する。
        if java.exists() && jar.exists() {
            Some(Assets { java, jar, web })
        } else {
            None
        }
    });

    bundled.unwrap_or_else(|| Assets {
        java: PathBuf::from(DEV_JAVA),
        jar: PathBuf::from(DEV_EDITOR_SERVER_JAR),
        web: PathBuf::from(DEV_EDITOR_WEB_DIST),
    })
}

struct ServerProc(Mutex<Option<Child>>);

#[cfg(unix)]
extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

// java 子プロセスをそのプロセスグループごと kill する。
// java を process_group(0) でグループリーダーにしてあるので、pid をそのまま
// 負の pgid として kill に渡せば、java が孫プロセスを作っていても巻き込んで倒せる。
#[cfg(unix)]
fn kill_process_group(child: &mut Child) {
    let pid = child.id() as i32;
    unsafe {
        // -pid = プロセスグループ全体。まず SIGTERM、取りこぼしに SIGKILL。
        kill(-pid, 15); // SIGTERM
    }
    std::thread::sleep(Duration::from_millis(300));
    unsafe {
        kill(-pid, 9); // SIGKILL
    }
    let _ = child.wait();
    SERVER_PGID.store(0, Ordering::SeqCst);
}

#[cfg(not(unix))]
fn kill_process_group(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

// ターミナルから launcher が SIGTERM/SIGINT/SIGHUP で倒される経路は Tauri の
// RunEvent::Exit を通らない。その時でも java を道連れにするための保険。
// シグナルハンドラ内で許されるのは async-signal-safe な処理だけなので、
// グローバルに保存した pgid へ kill(2) を撃つだけにして、そのまま既定動作で死ぬ。
#[cfg(unix)]
extern "C" fn on_term_signal(_sig: i32) {
    extern "C" {
        fn _exit(code: i32) -> !;
    }
    let pgid = SERVER_PGID.load(Ordering::SeqCst);
    if pgid > 0 {
        unsafe {
            kill(-pgid, 9); // SIGKILL: 確実に道連れ
        }
    }
    // GUI の run loop が自前のシグナル処理を持っていて再 raise が効かないことがある。
    // _exit は async-signal-safe で無条件に自分を終わらせるので、これで launcher も確実に落ちる。
    unsafe {
        _exit(0);
    }
}

#[cfg(unix)]
fn install_signal_handlers() {
    extern "C" {
        fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
    }
    // 15=SIGTERM 2=SIGINT 1=SIGHUP
    for sig in [15, 2, 1] {
        unsafe {
            signal(sig, on_term_signal);
        }
    }
}

#[cfg(not(unix))]
fn install_signal_handlers() {}

// TcpListener に 0 番ポートでバインドして OS が割り当てた空きポートを得る。
// listener はここで drop するので、直後に java が同じポートを掴める。
fn pick_free_port() -> std::io::Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    Ok(listener.local_addr()?.port())
}

fn spawn_editor_server(java: &Path, jar: &Path, port: u16, web: &str) -> std::io::Result<Child> {
    let mut cmd = Command::new(java);
    cmd.args([
        "-Djava.awt.headless=true",
        "-jar",
        &jar.to_string_lossy(),
    ])
    .env("EDITOR_PORT", port.to_string())
    .env("EDITOR_WEB", web)
    // EDITOR_DIR はあえて渡さない = プロジェクト未選択で起動し画面で選ばせる。
    // この Mac のシェルには存在しない nix パスの DEVELOPER_DIR/SDKROOT が刺さっており、
    // 子プロセスに漏らすと悪さをするので外す。
    .env_remove("DEVELOPER_DIR")
    .env_remove("SDKROOT")
    .stdout(Stdio::null())
    .stderr(Stdio::null());

    // 子を新しいプロセスグループのリーダーにする → 終了時にグループごと kill できる。
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }

    cmd.spawn()
}

// /health が 200 を返すまで待つ。java の cold start ぶんを見て ~20 秒でタイムアウト。
fn wait_for_health(port: u16, timeout: Duration) -> bool {
    let url = format!("http://127.0.0.1:{port}/health");
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        // curl は macOS 標準。--fail で HTTP エラーを非0終了に、-s で無音。
        let ok = Command::new("curl")
            .args(["-s", "-f", "-o", "/dev/null", "--max-time", "2", &url])
            .env_remove("DEVELOPER_DIR")
            .env_remove("SDKROOT")
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            return true;
        }
        std::thread::sleep(Duration::from_millis(300));
    }
    false
}

fn main() {
    let assets = resolve_assets();
    if !assets.jar.exists() {
        eprintln!(
            "[editor_app] editor_server の jar が見つかりません: {}\n\
             先にビルドしてください: cd editor_server && GITHUB_TOKEN=$(gh auth token) ../bin/flix build-fatjar",
            assets.jar.display()
        );
        std::process::exit(1);
    }
    eprintln!(
        "[editor_app] java={} jar={} web={}",
        assets.java.display(),
        assets.jar.display(),
        assets.web.display()
    );

    let port = pick_free_port().expect("空きポートの取得に失敗");
    eprintln!("[editor_app] 選択ポート = {port}");

    let web = assets.web.to_string_lossy().into_owned();
    let child = match spawn_editor_server(&assets.java, &assets.jar, port, &web) {
        Ok(c) => {
            eprintln!("[editor_app] editor_server 起動 pid={} port={port}", c.id());
            // process_group(0) で子は自分自身を pgid とするリーダーになる。
            SERVER_PGID.store(c.id() as i32, Ordering::SeqCst);
            install_signal_handlers();
            c
        }
        Err(e) => {
            eprintln!("[editor_app] editor_server の起動に失敗: {e}");
            std::process::exit(1);
        }
    };

    eprintln!("[editor_app] /health を待機中 (最大 20 秒)...");
    if !wait_for_health(port, Duration::from_secs(20)) {
        eprintln!("[editor_app] editor_server が起動しませんでした。子プロセスを片付けて終了します。");
        let mut child = child;
        kill_process_group(&mut child);
        std::process::exit(1);
    }
    eprintln!("[editor_app] /health OK。WebView を開きます。");

    let url = format!("http://127.0.0.1:{port}/");
    let external: tauri::Url = url.parse().expect("URL の生成に失敗");

    let app = tauri::Builder::default()
        .manage(ServerProc(Mutex::new(Some(child))))
        .invoke_handler(tauri::generate_handler![list_running_games])
        .setup(move |app| {
            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(external))
                .title("Flix GE Editor")
                .inner_size(1200.0, 820.0)
                .build()?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Tauri アプリのビルドに失敗");

    app.run(|app_handle, event| {
        if let RunEvent::Exit = event {
            if let Some(mut c) = app_handle.state::<ServerProc>().0.lock().unwrap().take() {
                kill_process_group(&mut c);
                eprintln!("[editor_app] editor_server (プロセスグループ) を kill しました。");
            }
        }
    });
}
