# Claude Code · 도티오 원클릭 인스톨러

비개발자가 30초 안에 Claude Code를 시작하도록 만든 원클릭 설치 도구.

- **다운로드**:
  - macOS: https://github.com/dotio-team/claude-installer/releases/latest/download/ClaudeCode-Installer.pkg
  - Windows: https://github.com/dotio-team/claude-installer/releases/latest/download/ClaudeCode-Installer.exe

## 무엇이 설치되나요

1. **Node.js 20 LTS** — 이미 있으면 건너뜁니다. 없으면 nodejs.org 공식 패키지를 받아 설치.
2. **Git** — macOS는 Xcode Command Line Tools, Windows는 Git for Windows 공식 인스톨러.
3. **`@anthropic-ai/claude-code`** — npm 글로벌 설치.
4. 한글 사용자명 대응 (Windows에서 `%USERPROFILE%`에 한글이 있으면 `C:\Users\Public\claude-code\`를 대신 사용).
5. 설치 로그를 사용자가 읽을 수 있는 위치에 저장:
   - macOS: `~/Library/Logs/ClaudeInstaller/install.log`
   - Windows: `%APPDATA%\ClaudeInstaller\install.log`

## 보안 경고 우회

코드 사이닝이 없어서 첫 실행 시 OS가 경고를 띄웁니다. 위험한 게 아니라, 도티오가 아직 코드 서명 인증서를 발급받지 않았기 때문입니다.

### macOS (Sequoia 이상)

1. `.pkg`를 더블클릭하면 "차단되었습니다" 알림이 뜨고 "완료"만 보입니다 → 일단 누릅니다.
2. `시스템 설정` → `개인정보 보호 및 보안`을 엽니다.
3. "보안" 섹션 맨 아래의 **"그래도 열기"** 버튼을 클릭합니다.
4. Touch ID 또는 비밀번호로 확인하면 인스톨러가 실행됩니다.

(터미널을 쓸 수 있다면 한 줄로도 됩니다: `sudo installer -pkg ~/Downloads/ClaudeCode-Installer.pkg -target /`)

### Windows

SmartScreen에서 "추가 정보" → "실행"

## 로컬에서 빌드하기

### macOS .pkg
```bash
bash installer/macos/build.sh
# 결과: installer/macos/dist/ClaudeCode-Installer.pkg
```

### Windows .exe
Windows 머신에서 [Inno Setup 6](https://jrsoftware.org/isinfo.php) 설치 후:
```cmd
cd installer\windows
iscc installer.iss
:: 결과: installer\windows\dist\ClaudeCode-Installer.exe
```

## 레포 구조

```
claude-installer/
├── installer/
│   ├── macos/              # productbuild로 .pkg 생성
│   │   ├── build.sh
│   │   ├── Distribution.xml
│   │   ├── scripts/postinstall
│   │   └── resources/{welcome,conclusion,license}.html
│   └── windows/            # Inno Setup으로 .exe 생성
│       ├── installer.iss
│       └── resources/{postinstall.cmd,claude-uninstall.cmd,license.txt}
└── web/public/             # 정적 랜딩페이지
    └── index.html
```

## 제거하기

- **macOS**: 터미널에서 `claude-uninstall` (설정까지 지우려면 `claude-uninstall --purge`)
- **Windows**: 설정 → 앱 → "Claude Code" → 제거

## 라이선스

MIT. 도티오는 Anthropic, PBC와 무관하며 Claude Code는 Anthropic의 상표입니다.
