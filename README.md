# WorktreeManager

Git worktree 관리를 위한 Ruby 젬입니다.

## 설치

```bash
gem install worktree_manager
```

또는 Gemfile에 추가:

```ruby
gem 'worktree_manager'
```

## 사용법

### 기본 사용법

```ruby
require 'worktree_manager'

# 매니저 생성
manager = WorktreeManager.new

# 또는 특정 리포지토리 경로 지정
manager = WorktreeManager.new("/path/to/repository")
```

### Worktree 목록 조회

```ruby
worktrees = manager.list
worktrees.each do |worktree|
  puts worktree.to_s
end
```

### Worktree 추가

```ruby
# 새 브랜치로 worktree 추가
manager.add("../feature-branch", "feature/new-feature")

# 기존 브랜치로 worktree 추가
manager.add("../hotfix", "hotfix/urgent-fix")
```

### Worktree 제거

```ruby
manager.remove("../feature-branch")
```

### Worktree 정리

```ruby
manager.prune
```

## API

### WorktreeManager::Manager

#### `#initialize(repository_path = ".")`
Git 리포지토리 경로를 받아 매니저 인스턴스를 생성합니다.

#### `#list`
현재 워크트리 목록을 반환합니다.

#### `#add(path, branch = nil)`
새로운 워크트리를 추가합니다.

#### `#remove(path)`
워크트리를 제거합니다.

#### `#prune`
더 이상 존재하지 않는 워크트리를 정리합니다.

### WorktreeManager::Worktree

워크트리 정보를 나타내는 클래스입니다.

#### 메서드

- `#path` - 워크트리 경로
- `#branch` - 브랜치 이름
- `#head` - HEAD 커밋 해시
- `#detached?` - detached HEAD 상태 여부
- `#bare?` - bare 리포지토리 여부
- `#main?` - main/master 브랜치 여부
- `#exists?` - 디렉토리 존재 여부
- `#to_s` - 문자열 표현
- `#to_h` - 해시 표현

## 개발

```bash
# 의존성 설치
bundle install

# 테스트 실행
bundle exec rspec

# 젬 빌드
gem build worktree_manager.gemspec
```

## 라이센스

MIT 라이센스입니다.
