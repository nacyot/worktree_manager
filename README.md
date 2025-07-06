# 🌳 Worktree Manager

Git worktree를 쉽게 관리할 수 있는 Ruby CLI 도구입니다.

## ✨ 주요 기능

- 🚀 **간편한 CLI**: `wm` 명령어로 worktree 관리
- 🪝 **Hook 시스템**: worktree 생성/삭제 시 자동 스크립트 실행
- 🔍 **Verbose 로깅**: 상세한 디버그 정보 제공
- 🛡️ **에러 방지**: 브랜치 중복, 경로 충돌 자동 검사
- ⚡ **성능 측정**: Hook 실행 시간 모니터링
- 🧪 **완전한 테스트**: 53개 유닛 테스트 + 통합 테스트

## 📦 설치

```bash
gem install worktree_manager
```

또는 Gemfile에 추가:

```ruby
gem 'worktree_manager'
```

## 🚀 사용법

### 기본 명령어

```bash
# 버전 확인
wm version

# worktree 목록 보기
wm list

# worktree 생성 (기존 브랜치)
wm add ../feature-branch feature/existing

# worktree 생성 (새 브랜치)
wm add ../new-feature -b feature/new

# worktree 삭제
wm remove ../feature-branch

# 도움말
wm help
```

### 고급 옵션

```bash
# 강제 생성 (기존 디렉터리 덮어쓰기)
wm add ../hotfix --force

# 상세 로그와 함께 실행
wm add ../debug-feature -b debug/test --verbose

# 강제 삭제 (변경사항이 있어도)
wm remove ../old-feature --force
```

## 🪝 Hook 시스템

worktree 생성/삭제 시 자동으로 스크립트를 실행할 수 있습니다.

### Hook 설정 파일

`.worktree_hooks.yml` 파일을 프로젝트 루트에 생성:

```yaml
# worktree 생성 전 실행
pre_add:
  command: "echo '🌿 Worktree 생성 시작: $WORKTREE_PATH'"
  stop_on_error: true

# worktree 생성 후 실행
post_add:
  - "bundle install"
  - "echo '✅ 설정 완료: $WORKTREE_BRANCH'"

# worktree 삭제 전 실행
pre_remove:
  command: "git stash push -m 'Auto stash before removal'"

# worktree 삭제 후 실행
post_remove:
  - "echo '🗑️ 정리 완료: $WORKTREE_PATH'"
```

### 사용 가능한 환경 변수

- `$WORKTREE_PATH`: worktree 경로
- `$WORKTREE_BRANCH`: 브랜치명
- `$WORKTREE_MANAGER_ROOT`: 메인 저장소 경로
- `$WORKTREE_FORCE`: 강제 옵션 여부
- `$WORKTREE_SUCCESS`: 작업 성공 여부 (post hook에서만)

### 실용적인 Hook 예제

```yaml
# 개발 환경 자동 설정
post_add:
  - "bundle install"              # 의존성 설치
  - "cp .env.example .env"        # 환경 변수 파일 복사
  - "code $WORKTREE_PATH"         # VS Code로 열기

# 작업 내용 자동 백업
pre_remove:
  - "git add -A"
  - "git stash push -m 'Auto backup: $WORKTREE_BRANCH'"

# 알림 발송
post_add:
  - "osascript -e 'display notification \"워크스페이스 준비 완료\" with title \"$WORKTREE_BRANCH\"'"
```

## 🔍 디버깅

### Verbose 모드

`--verbose` 또는 `-v` 옵션으로 상세한 실행 정보를 확인할 수 있습니다:

```bash
wm add ../debug-workspace -b debug/issue-123 --verbose
```

출력 예시:
```
[15:42:52.168] [DEBUG] 🪝 Hook 실행 시작: pre_add
[15:42:52.168] [DEBUG] 📋 Hook 설정: {"command" => "echo 'Starting...'"}
[15:42:52.168] [DEBUG] 🔧 컨텍스트: {path: "../debug-workspace", branch: "debug/issue-123"}
[15:42:52.177] [DEBUG] ⏱️ 실행 시간: 9.08ms
[15:42:52.177] [DEBUG] ✅ Hook 실행 완료: pre_add (결과: true)
```

## 🛡️ 에러 방지

Worktree Manager는 다양한 에러 상황을 자동으로 검사합니다:

- ❌ **빈 경로 입력**
- ❌ **잘못된 브랜치명** (공백, 특수문자)
- ❌ **기존 디렉터리 충돌**
- ❌ **브랜치 중복 사용**
- ❌ **메인 저장소 삭제 시도**

### 에러 메시지 예시

```bash
$ wm add existing-dir -b new-branch
Error: Directory 'existing-dir' already exists and is not empty
  Use --force to override or choose a different path

$ wm add ../test -b "invalid branch"
Error: Invalid branch name 'invalid branch'. Branch names cannot contain spaces or special characters.
```

## 📋 CLI 명령어 레퍼런스

### `wm version`
현재 설치된 버전을 표시합니다.

### `wm list`
현재 Git 저장소의 모든 worktree 목록을 표시합니다.

**요구사항**: 메인 Git 저장소에서만 실행 가능

### `wm add PATH [BRANCH]`
새로운 worktree를 생성합니다.

**인수**:
- `PATH`: worktree를 생성할 경로
- `BRANCH`: 사용할 브랜치 (선택사항)

**옵션**:
- `-b, --branch BRANCH`: 새 브랜치를 생성하여 사용
- `-f, --force`: 기존 디렉터리가 있어도 강제 생성
- `-v, --verbose`: 상세한 실행 로그 출력

**예시**:
```bash
wm add ../feature-api feature/api        # 기존 브랜치 사용
wm add ../new-feature -b feature/new     # 새 브랜치 생성
wm add ../override --force               # 강제 생성
```

### `wm remove PATH`
기존 worktree를 삭제합니다.

**인수**:
- `PATH`: 삭제할 worktree 경로

**옵션**:
- `-f, --force`: 변경사항이 있어도 강제 삭제
- `-v, --verbose`: 상세한 실행 로그 출력

**예시**:
```bash
wm remove ../feature-api                 # 일반 삭제
wm remove ../old-feature --force         # 강제 삭제
```

## 🧪 개발 및 테스트

### 개발 환경 설정

```bash
# 저장소 클론
git clone https://github.com/username/worktree_manager.git
cd worktree_manager

# 의존성 설치
bundle install

# 테스트 실행
bundle exec rspec

# 젬 빌드
gem build worktree_manager.gemspec

# 로컬 설치
gem install worktree_manager-*.gem
```

### 테스트 커버리지

- **53개 유닛 테스트**: 모든 핵심 기능 검증
- **통합 테스트**: 실제 Git 환경에서 동작 확인
- **에러 처리 테스트**: 다양한 에러 상황 시뮬레이션
- **Hook 시스템 테스트**: 환경 변수 전달 및 실행 검증

### 성능 벤치마크

- Hook 실행 시간: 평균 10ms 이하
- Worktree 생성: 평균 250ms 이하
- Worktree 삭제: 평균 220ms 이하

## 🤝 기여하기

1. Fork 저장소
2. 기능 브랜치 생성 (`git checkout -b feature/amazing-feature`)
3. 변경사항 커밋 (`git commit -m 'Add amazing feature'`)
4. 브랜치에 Push (`git push origin feature/amazing-feature`)
5. Pull Request 생성

## 🙏 감사의 말

- Git worktree 기능을 제공하는 Git 팀
- Ruby 및 RSpec 커뮤니티
- 모든 기여자들

---

**🌟 Worktree Manager로 더 효율적인 Git 워크플로우를 경험하세요!**
