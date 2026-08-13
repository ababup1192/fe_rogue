#!/usr/bin/env python3
"""Windows 実機で bin/checkd 一式が動くかを 1 回で確かめる検査。

使い方 (リポジトリのどこからでも):

    python bin/verify-win-checkd.py

やること (前の段階が失敗しても後続を試し、最後にまとめを出す):
  a. Python と OS の情報
  b. java と bin/flix.jar の所在
  c. flix repl が素のパイプで応答するか (番兵方式で 1 回)
  d. bin/checkd の冷スタート → PING → CHECK 緑
  e. 壊れた小パッケージで CHECK 赤が exit 1 になるか
  f. checkd --stop で常駐が消えるか

リポジトリのファイルは一切変更しない。試し用のパッケージは一時ディレクトリに
作り、終わったら消す。結果の文字列をそのまま貼って報告できる形で出す。
"""

import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
CHECKD = os.path.join(ROOT, "bin", "checkd")
FLIX_JAR = os.path.join(ROOT, "bin", "flix.jar")

RESULTS = []


def report(step, ok, detail, sec=None):
    mark = "OK" if ok else "NG"
    line = f"[{step}] {mark}"
    if sec is not None:
        line += f" ({sec:.1f}s)"
    line += f" {detail}"
    print(line, flush=True)
    RESULTS.append((step, ok, detail))


def state_dir(pkg):
    h = hashlib.sha1(os.path.realpath(pkg).encode("utf-8")).hexdigest()[:16]
    return os.path.join(os.path.expanduser("~/.cache/flix-checkd"), h)


def tcp_ping(pkg, timeout=2.0):
    """port ファイル経由で常駐へ PING。応答が読めたら True。"""
    with open(os.path.join(state_dir(pkg), "port"), encoding="utf-8") as f:
        port = int(f.read().strip())
    s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    s.settimeout(timeout)
    try:
        s.sendall(b"PING\n")
        buf = b""
        while b"\n" not in buf:
            c = s.recv(4096)
            if not c:
                return False
            buf += c
        return buf.startswith(b"RES 0")
    finally:
        s.close()


def make_pkg(base, name, source, flix_version):
    pkg = os.path.join(base, name)
    os.makedirs(os.path.join(pkg, "src"))
    with open(os.path.join(pkg, "flix.toml"), "w", encoding="utf-8") as f:
        f.write(
            "[package]\n"
            f'name        = "{name}"\n'
            'description = "verify-win-checkd temporary package"\n'
            'version     = "0.1.0"\n'
            f'flix        = "{flix_version}"\n'
            'authors     = ["verify"]\n')
    with open(os.path.join(pkg, "src", "Main.flix"), "w", encoding="utf-8") as f:
        f.write(source)
    return pkg


def run_cmd(args, cwd, timeout):
    t0 = time.time()
    try:
        proc = subprocess.run(args, cwd=cwd, capture_output=True,
                              timeout=timeout)
        out = (proc.stdout + proc.stderr).decode("utf-8", "replace")
        return proc.returncode, out, time.time() - t0
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, repr(e), time.time() - t0


def step_a():
    import platform
    detail = (f"Python {platform.python_version()} / {platform.platform()} "
              f"/ os.name={os.name} / exe={sys.executable}")
    report("a", True, detail)


def step_b():
    java = shutil.which("java")
    if not java:
        report("b", False, "java が PATH に見つからない")
        return None, None
    code, out, sec = run_cmd([java, "-version"], ROOT, 60)
    jar_ok = os.path.isfile(FLIX_JAR)
    ver = None
    if jar_ok:
        code2, out2, _ = run_cmd([java, "-jar", FLIX_JAR, "--version"], ROOT, 120)
        m = re.search(r"(\d+\.\d+\.\d+)", out2 or "")
        if code2 == 0 and m:
            ver = m.group(1)
    ok = (code == 0) and jar_ok
    detail = (f"java={java} / flix.jar={'あり' if jar_ok else '無い'}"
              f" / flix version={ver or '読めず'}")
    report("b", ok, detail, sec)
    return (java if ok else None), (ver or "0.75.1")


def step_c(java, pkg):
    """repl と素のパイプで話せるか。番兵コマンドを送り、応答に番兵名が返るのを待つ。"""
    t0 = time.time()
    env = os.environ.copy()
    env["JAVA_TOOL_OPTIONS"] = (
        env.get("JAVA_TOOL_OPTIONS", "") + " -Djava.awt.headless=true").strip()
    try:
        proc = subprocess.Popen(
            [java, "-jar", FLIX_JAR, "repl"], cwd=pkg,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, env=env, bufsize=0)
    except OSError as e:
        report("c", False, f"repl を起動できない: {e!r}", time.time() - t0)
        return
    chunks = []
    done = threading.Event()

    def pump():
        while True:
            try:
                c = proc.stdout.read(65536)
            except (OSError, ValueError):
                break
            if not c:
                break
            chunks.append(c)
            if b"zzz-sentinel" in b"".join(chunks):
                done.set()

    threading.Thread(target=pump, daemon=True).start()
    ok = False
    try:
        proc.stdin.write(b":zzz-sentinel\n")
        proc.stdin.flush()
        ok = done.wait(timeout=600)
    except OSError:
        pass
    finally:
        try:
            proc.stdin.write(b":quit\n")
            proc.stdin.flush()
        except OSError:
            pass
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    sec = time.time() - t0
    tail = b"".join(chunks)[-200:].decode("utf-8", "replace").replace("\n", " ")
    report("c", ok, "repl が番兵に応答" if ok else f"番兵が返らない: …{tail}", sec)


def step_d(good_pkg):
    code, out, sec = run_cmd([sys.executable, CHECKD, good_pkg], good_pkg, 900)
    if code != 0:
        report("d", False, f"冷スタートの CHECK が exit {code}: {out[-300:]}", sec)
        return
    try:
        ping_ok = tcp_ping(good_pkg)
    except (OSError, ValueError) as e:
        report("d", False, f"CHECK は緑だが PING できない: {e!r}", sec)
        return
    code2, out2, sec2 = run_cmd([sys.executable, CHECKD, good_pkg], good_pkg, 120)
    ok = ping_ok and code2 == 0
    report("d", ok,
           f"冷 {sec:.1f}s → PING {'応答' if ping_ok else '不応答'} → "
           f"温 CHECK exit {code2} ({sec2:.1f}s)", sec + sec2)


def step_e(bad_pkg):
    code, out, sec = run_cmd([sys.executable, CHECKD, bad_pkg], bad_pkg, 900)
    ok = code == 1
    has_err = bool(re.search(r"^-- .*\bError\b", out or "", re.M))
    report("e", ok,
           f"壊れたパッケージの CHECK が exit {code} (期待 1) / "
           f"エラー見出し{'あり' if has_err else '無し'}", sec)


def step_f(pkgs):
    ok = True
    details = []
    for pkg in pkgs:
        code, out, _ = run_cmd([sys.executable, CHECKD, "--stop", pkg], ROOT, 60)
        alive = os.path.isfile(os.path.join(state_dir(pkg), "port"))
        if code != 0 or alive:
            ok = False
        details.append(f"{os.path.basename(pkg)}: exit {code}"
                       f"{' (port 残存)' if alive else ''}")
    report("f", ok, " / ".join(details))


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    print("== verify-win-checkd ==", flush=True)
    step_a()
    java, flix_ver = step_b()
    base = tempfile.mkdtemp(prefix="verify-checkd-")
    good = make_pkg(base, "verify_good",
                    'def main(): Unit \\ IO = println("verify")\n', flix_ver)
    bad = make_pkg(base, "verify_bad",
                   'def broken(): Int32 = "not a number"\n', flix_ver)
    try:
        if java:
            step_c(java, good)
        else:
            report("c", False, "java が無いので飛ばした")
        if os.path.isfile(CHECKD):
            step_d(good)
            step_e(bad)
            step_f([good, bad])
        else:
            report("d", False, f"{CHECKD} が無い")
    finally:
        # 常駐が残るとマシンが重くなるので、途中で落ちても止めてから帰る
        for pkg in (good, bad):
            try:
                subprocess.run([sys.executable, CHECKD, "--stop", pkg],
                               capture_output=True, timeout=60)
            except (OSError, subprocess.TimeoutExpired):
                pass
        shutil.rmtree(base, ignore_errors=True)
    print("\n== まとめ ==")
    for step, ok, detail in RESULTS:
        print(f"  {step}: {'OK' if ok else 'NG'} — {detail}")
    all_ok = all(ok for _, ok, _ in RESULTS)
    if os.name == "nt" and not all_ok:
        print("\n参考: bin/flix は bash スクリプトなので、Windows で d/e が NG の場合は"
              "\ncheckd が repl の起動口 (flix_bin) を Windows で解決できていない疑いが濃い。")
    print(f"\n結果: {'全部 OK' if all_ok else 'NG あり (上のまとめを貼って報告してください)'}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
