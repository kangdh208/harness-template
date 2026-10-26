# harness-template

AI Agent를 개발하는 프로젝트에 붙이는 Claude Code 하네스의 원본. 현재 버전은 [VERSION](VERSION), 변경 내역은 [CHANGELOG.md](CHANGELOG.md).

"하네스 엔지니어링 등록해줘" 한 마디면 두 층이 구성된다.

| 층 | 내용 | 어떻게 만들어지나 |
|---|---|---|
| **공통 기반** | planner / reviewer / tester, 계획 → 검증 → 인계 → 개선 루프, format·lint·test 훅 | 모든 프로젝트에 같은 것을 설치. 업데이트 때 교체 |
| **도메인 팀** | 프로젝트의 세부 도메인에 맞춘 `team-*` 에이전트와 워크플로 스킬 | 도메인을 인터뷰하고 설계안을 확인받은 뒤 생성. 업데이트 때 보존 |

대도메인은 **AI Agent**로 고정되어 있다. 세부 도메인(무엇을 하는 에이전트인지, 핵심 동작, 가장 어려운 부분)은 등록할 때마다 선택지 없이 열린 질문으로 묻는다. 스택 같은 것은 코드에서 추론한다.

아래는 선택지가 아니라 설계의 출발점으로 쓰는 예시다. 맞는 예시가 없으면 답변에서 팀을 직접 설계한다.

| 유형 예시 | 기본 팀 (공통 역할 + 유형 전용 역할) |
|---|---|
| 대화형·RAG | prompt-engineer, eval-designer, **retrieval-engineer** |
| 도구 사용·업무 자동화 (function calling, MCP) | prompt-engineer, eval-designer, **tool-designer** (+ safety-reviewer) |
| 멀티에이전트 오케스트레이션 | **agent-architect**, prompt-engineer, eval-designer |
| Claude Code 확장 (스킬, 훅, 플러그인) | **skill-author**, eval-designer |
| 음성·실시간 | prompt-engineer, eval-designer, **latency-engineer** |

개발 단계(새로 만들기 / 개선 / 품질 문제), 품질 우선순위(정확성 / 안전성 / 비용·지연 / 평가 자동화), 팀 규모에 따라 이 구성을 조정한다. 자세한 기준은 [ai-agent-domains.md](global-skill/harness/references/ai-agent-domains.md)에 있다.

## 사용법

| 요청 | 하는 일 |
|---|---|
| 하네스 엔지니어링 등록해줘 | 기반 설치 → 코드 분석 → 도메인 인터뷰 → 팀 설계안 확인 → 팀 생성 |
| 하네스 업데이트해줘 | 템플릿 변경을 반영한다. context, state, 설정값, 도메인 팀은 보존한다 |
| 에이전트 추가해줘 / 팀 재구성해줘 | 도메인 팀을 확장하거나 다시 설계한다 |
| 하네스 점검해줘 | 설치 상태, 설정, 팀 정의, 문서와 코드의 불일치를 확인한다 |
| 하네스 제거해줘 | 하네스 파일과 팀을 지운다 (`-KeepData` 로 보존 가능) |

등록한 뒤 프로젝트 안에서는:

| 명령 | 언제 |
|---|---|
| `/harness-plan` | 여러 파일에 걸치거나 3단계 이상인 작업을 시작할 때 |
| `/harness-verify` | 완료를 보고하기 전에 |
| `/harness-handoff` | 작업 단위를 마치거나 세션을 끝낼 때 |
| `/harness-evolve` | 같은 피드백이나 실패가 반복될 때 |
| `/team-*` | 도메인 워크플로 (생성된 경우. 예: 프롬프트 개선 사이클) |

전역 스킬 `~/.claude/skills/harness` 가 이 과정을 진행한다. 원본은 `global-skill/harness/` 에 있다.

스크립트를 직접 실행할 때 (공통 기반만 다룬다. 도메인 팀은 스킬이 만든다):

```powershell
.\install.ps1   -Target C:\path\to\project               # .gitignore 에 등록
.\install.ps1   -Target C:\path\to\project -UseExclude   # .git/info/exclude 에 등록
.\doctor.ps1    -Target C:\path\to\project               # 설치 상태 점검 (읽기 전용)
.\uninstall.ps1 -Target C:\path\to\project [-KeepData]
```

## 작업 흐름

```
이해 ──▶ 계획 ──────────────▶ 구현 ──▶ 검증 ──────────────────▶ 기록
         /harness-plan                /harness-verify            /harness-handoff
         ├ planner                    ├ lint, test
         └ team-* (루프 연결: 계획)    ├ reviewer ∥ tester
                                      ├ team-* (루프 연결: 검증)
           편집마다 훅: format → lint   └ 최대 3회 수정·재검증

                                반복된 피드백 ──▶ /harness-evolve
                                                  ├ context 의 "학습된 규칙"
                                                  └ team-* 정의, 루프 연결
```

공통 스킬은 팀 에이전트 이름을 모른다. 대신 `.harness/context/domain.md` 의 **루프 연결**("어떤 변경이면 → 어떤 에이전트 → 무엇을 위해")을 읽고 호출한다. 그래서 공통 기반을 업데이트해도 팀 연결은 유지된다.

## 설계 원칙

[revfactory/harness](https://github.com/revfactory/harness) v2에서 가져온 원칙이다.

- 에이전트에는 **누가** 일하는지를, 스킬에는 **어떻게** 하는지를 적는다.
- 에이전트 정의는 같은 구조를 따른다: 핵심 역할 / 작업 원칙(이유 포함) / 입력·출력 / 다시 호출할 때 / 오류 처리.
- 모델은 에이전트의 중요도가 아니라 업무 성격으로 고르고, 이유를 frontmatter 주석으로 남긴다.
- 읽기 전용 에이전트는 `disallowedTools` 로 수정 도구를 막는다.
- description에는 하는 일, 호출 표현, **쓰지 않는 경우**를 함께 적는다.
- 검토 지적은 반박 검증을 거치고 `확인됨`/`추정` 을 표시한다.
- 피드백은 사례별 규칙이 아니라 원리로 일반화해서, 한 번에 하나씩 반영한다.

| 공통 에이전트 | 맡는 일 | 모델 | 파일 수정 |
|---|---|---|---|
| `harness-planner` | 큰 작업의 설계·분해 | opus | 안 함 |
| `harness-reviewer` | 버그, 회귀, 계약 불일치, 도메인 점검 항목 검토 | opus | 안 함 |
| `harness-tester` | 테스트 작성·실행, 실패 원인 분류 | sonnet | 테스트 파일만 |

## 등록하면 프로젝트에 생기는 것

```
프로젝트/
├── .harness/
│   ├── HARNESS.md                 작업 원칙                   (교체)
│   ├── hooks/                     format·lint, test 훅        (교체)
│   ├── VERSION                                                (교체)
│   ├── harness.config.json        검증 명령                   (보존, 새 키만 추가)
│   ├── context/                   project, architecture,      (보존, 새 파일만 추가)
│   │                              conventions, domain
│   ├── state/                     진행·결정 기록              (보존)
│   └── workspace/                 팀 워크플로 중간 산출물      (보존)
├── .claude/
│   ├── agents/harness-*.md        공통 에이전트               (교체)
│   ├── agents/team-*.md           도메인 팀                   (보존)
│   ├── skills/harness-*/          공통 스킬                   (교체)
│   ├── skills/team-*/             도메인 워크플로             (보존)
│   └── settings.local.json        훅 등록 (기존 설정과 병합)
├── CLAUDE.local.md                .harness 문서 import 블록
└── .gitignore                     위 경로를 묶은 ignore 블록
```

- 프로젝트의 `CLAUDE.md` 와 `settings.json` 은 건드리지 않는다. `*.local.*` 파일과 `harness-`·`team-` 접두사 파일만 쓴다.
- "교체"되는 파일을 프로젝트에서 직접 고치면 다음 업데이트 때 사라진다. 프로젝트 전용 규칙은 `.harness/context/` 에, 팀 조정은 `team-*` 에 둔다. `/harness-evolve` 가 이렇게 나눠 반영한다.

## harness.config.json

| 키 | 의미 |
|---|---|
| `format` | 파일 편집 후 실행. 실패해도 무시한다. `{file}` 은 편집한 파일 경로 |
| `lint` | 파일 편집 후 실행. 실패하면 출력이 Claude에게 전달돼 바로 고친다 |
| `test` | `/harness-verify` 와 종료 훅에서 실행 |
| `verifyOnStop` | true면 응답이 끝날 때마다 `test` 실행. 테스트가 30초 안쪽일 때만 권장 |

## 템플릿 수정

1. 이 폴더를 고친다. 동작이 바뀌면 `VERSION` 을 올리고 `CHANGELOG.md` 에 적는다.
2. 각 프로젝트에서 "하네스 업데이트해줘"라고 하면 반영된다.
3. 전역 스킬을 고쳤다면 `global-skill/harness/` 폴더 전체(references 포함)를 `~/.claude/skills/harness/` 로 다시 복사한다.

| 고칠 것 | 위치 |
|---|---|
| 모든 프로젝트의 작업 루프 | `HARNESS.md`, `agents/`, `skills/`, `hooks/` |
| 인터뷰 질문, 공통 역할, 유형별 팀 구성 예시 | `global-skill/harness/references/ai-agent-domains.md` |
| 팀 에이전트·워크플로 템플릿, 모델 선택, 검증 | `global-skill/harness/references/team-design.md` |
| 등록·업데이트·점검 절차 | `global-skill/harness/SKILL.md` |
