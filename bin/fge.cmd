@echo off
rem fge — bin/ の検査・要約ツールの呼び口 (Windows の cmd / PowerShell 用)。
rem 隣の bin/fge (sh) と同じことをする。中身は全部 bin\fge-go.exe が持っている。
rem
rem WhyNot: sh の方に任せないのは、Windows の素の cmd に sh が無いため
rem (Git Bash からは bin/fge の方が呼ばれる)。
setlocal
set "here=%~dp0"
set "go=%here%fge-go.exe"

if not exist "%go%" (
  echo fge: bin\fge-go.exe がありません。>&2
  echo      engine のリポジトリなら: make go-build>&2
  echo      ゲームのリポジトリなら:   engine 側で make sync-agents GAME^=%CD%>&2
  exit /b 127
)

"%go%" %*
exit /b %ERRORLEVEL%
