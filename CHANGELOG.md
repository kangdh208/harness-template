# Changelog

## 2.2.0 — 2026-10-27

하네스는 나만 쓰고 프로젝트는 팀이 함께 진행하는 환경에 맞췄다. 하네스는 내 변경에만 작동한다.

### 변경
- ignore 기본 위치를 `.git/info/exclude` 로 바꿨다 (커밋되지 않아 팀에 보이지 않음). `.gitignore` 는 `-UseGitignore` 를 붙일 때만 쓴다. `-UseExclude` 는 예전 명령 호환용으로 남겼다.
- 업데이트할 때 예전 버전이 `.gitignore` 에 넣은 하네스 블록을 exclude로 옮긴다 (`GITIGNORE_BLOCK_REMOVED`).
- worktree·submodule(`.git` 이 파일인 경우)의 exclude 경로를 찾는다.
- 편집 훅: `{file}` 이 없는 format·lint는 실행하지 않는다. 프로젝트 전체 format은 팀원 파일을 바꾸고, 전체 lint는 팀원 코드의 오류로 작업을 막기 때문이다.
- 종료 훅: 작업 트리에 변경이 없으면 건너뛴다. 실패하면 내 변경 파일 목록을 함께 전달하고, 팀원 코드의 실패는 고치지 말고 보고하라고 지시한다.
- HARNESS.md: "내 작업 범위"(작업 트리 + push하지 않은 커밋)와 "Git" 규칙(요청 시에만 커밋·push, 공유 브랜치 직접 push 금지, force push·`--no-verify` 금지, staged 목록 확인, 커밋 계정 확인)을 추가했다.
- verify / reviewer / tester: 내 변경만 검증·검토한다. 범위 밖 실패는 따로 보고하고 고치지 않는다. planner는 팀원 코드를 바꿔야 하는 단계를 위험 요소로 표시한다.
- doctor.ps1: `.gitignore` 에 남은 블록(팀에 보임), git에 추적되는 하네스 파일(FAIL), `{file}` 없는 format·lint를 점검한다.
- 전역 스킬: 등록할 때 저장소의 커밋 계정을 확인해 보고한다.

## 2.1.0 — 2026-10-26

하네스를 "공통 기반 + 도메인 팀" 두 층으로 나눴다. 대도메인 AI Agent 안의 세부 유형을 인터뷰해 프로젝트 전용 에이전트 팀을 만든다.

### 추가
- 도메인 인터뷰: 세부 도메인(무엇을 하는 에이전트인지, 핵심 동작, 가장 어려운 부분)을 매번 열린 질문으로 묻는다. 그다음 단계 / 품질 우선순위 / 팀 규모를 묻는다. 스택은 코드에서 추론한다.
- 유형 카탈로그는 선택지가 아니라 설계의 출발점이다. 맞는 예시가 없으면 답변에서 팀을 직접 설계한다.
- 팀 설계·생성: 설계안을 확인받은 뒤 `.claude/agents/team-*`, `.claude/skills/team-*` 를 만든다. 업데이트 때 보존된다.
- `context/domain.md`: 도메인, 팀 표, 루프 연결, 도메인 점검, 변경 이력. `CLAUDE.local.md` 로 import된다.
- 전역 스킬 references: `ai-agent-domains.md` (유형 카탈로그와 공통 역할), `team-design.md` (템플릿, 실행 모드, 모델 선택, 검증).
- doctor.ps1: domain.md 팀 표와 `team-*` 파일 대조, frontmatter name·description 확인.

### 변경
- `/harness-plan`, `/harness-verify` 가 domain.md 의 "루프 연결"을 읽고 해당 조건일 때만 팀 에이전트를 호출한다.
- reviewer가 domain.md 의 "도메인 점검" 항목도 본다.
- `/harness-evolve` 가 `team-*` 정의와 루프 연결을 직접 조정한다. 에이전트 추가·삭제는 전역 스킬로 안내한다.
- install.ps1: 보존 폴더(context, state)에 새 템플릿 파일이 있으면 추가한다 (`ADDED_FILES`). 기존 프로젝트를 업데이트하면 `domain.md` 가 생겨 인터뷰로 이어진다.
- ignore 블록에 `team-*` 추가. uninstall.ps1 은 `-KeepData` 가 없으면 `team-*` 도 지운다.

## 2.0.0 — 2026-10-26

[revfactory/harness](https://github.com/revfactory/harness) v2의 설계 원칙을 반영해 정리했다.

### 추가
- `harness-evolve` 스킬: 반복된 피드백과 실패를 원리로 일반화해 `.harness/context` 와 설정에 반영한다.
- `doctor.ps1`: 설치 상태 점검 (파일, 훅, import 블록, ignore, 미작성 문서, 설정 누락 키, 버전).
- `VERSION`: 업데이트할 때 `VERSION: 이전 -> 새 버전` 을 출력한다.
- `conventions.md` 에 "학습된 규칙" 섹션.

### 변경
- 에이전트 정의를 공통 구조로 다시 썼다: 핵심 역할 / 작업 원칙(이유 포함) / 입력·출력 / 다시 호출할 때 / 오류 처리.
- 에이전트별 모델을 업무 성격에 맞게 지정했다: planner·reviewer는 opus, tester는 sonnet. 근거는 frontmatter 주석에 있다.
- planner·reviewer는 `disallowedTools` 로 파일 수정 도구를 막았다. 셸은 쓸 수 있어 `git diff` 등을 실행할 수 있다.
- reviewer: 연결 지점의 계약 대조(생산자와 소비자를 함께 읽기)를 최우선으로 보고, 보고 전에 지적마다 반박 검증을 거친다. 지적에 `확인됨`/`추정` 을 표시하고, 검토하지 않은 범위를 밝힌다.
- tester: 수정 범위를 테스트 파일로 한정했다. 실패 원인을 테스트/구현/환경으로 구분한다.
- 스킬 description에 호출 조건, 후속 요청 표현, 쓰지 않는 경우를 함께 적었다.
- `harness-verify`: 결과를 통과/실패/미검증으로 나누고, 수정·재검증은 최대 3회로 제한했다.
- `harness-plan`: 진행 중인 목표가 있는지 먼저 확인한다 (새 계획 / 수정 / 충돌).
- `HARNESS.md`: 규칙마다 이유를 달았다. 서브에이전트 표와 실패 처리 원칙을 추가했다.
- 전역 `harness` 스킬: 0단계 현황 점검, `하네스 점검` 모드, 결과 점검표를 추가했다.
- `install.ps1`: 업데이트할 때 템플릿에 새로 생긴 설정 키를 프로젝트 `harness.config.json` 에 추가한다 (기존 값은 유지). 복사한 스킬의 `{{TEMPLATE_DIR}}` 를 템플릿 경로로 치환한다.

## 1.0.0

- 첫 버전: planner / reviewer / tester, /harness-plan · /harness-verify · /harness-handoff, format·lint·test 훅.
