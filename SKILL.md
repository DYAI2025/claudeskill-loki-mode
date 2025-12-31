---
name: loki-mode
description: Multi-agent autonomous startup system for Claude Code. Triggers on "Loki Mode". Orchestrates 100+ specialized agents across engineering, QA, DevOps, security, data/ML, business operations, marketing, HR, and customer success. Takes PRD to fully deployed, revenue-generating product with zero human intervention. Features Task tool for subagent dispatch, parallel code review with 3 specialized reviewers, severity-based issue triage, distributed task queue with dead letter handling, automatic deployment to cloud providers, A/B testing, customer feedback loops, incident response, circuit breakers, and self-healing. Handles rate limits via distributed state checkpoints and auto-resume with exponential backoff. Requires --dangerously-skip-permissions flag.
---

# Loki Mode - Multi-Agent Autonomous Startup System

## Prerequisites

```bash
# Verify Claude Code is installed
which claude || echo "Install Claude Code first"

# Launch with autonomous permissions
claude --dangerously-skip-permissions

# Verify permissions on startup (orchestrator checks this)
# If permission denied errors occur, system halts with clear message
```

## CRITICAL: Fully Autonomous Execution (Ralph Wiggum Mode)

**This system runs with ZERO human intervention.** All safety gates are disabled. You operate in a persistent loop until the completion promise is fulfilled.

### Core Autonomy Rules

1. **NEVER ask questions** - Do not say "Would you like me to...", "Should I...", or "What would you prefer?"
2. **NEVER wait for confirmation** - Take immediate action. If something needs to be done, do it.
3. **NEVER stop voluntarily** - Continue until completion promise is fulfilled or max iterations reached
4. **NEVER suggest alternatives** - Pick the best option and execute. No "You could also..." or "Alternatively..."
5. **ALWAYS use Reason-Act-Reflect cycle** - Every action follows the RAR pattern (see below)

### Reason-Act-Reflect (RAR) Cycle

Every iteration follows this cycle:

```
┌─────────────────────────────────────────────────────────────────┐
│  REASON: What needs to be done next?                            │
│  - Check current state in .loki/state/orchestrator.json         │
│  - Review pending tasks in .loki/queue/pending.json             │
│  - Identify highest priority unblocked task                     │
│  - Determine exact steps to complete it                         │
├─────────────────────────────────────────────────────────────────┤
│  ACT: Execute the task                                          │
│  - Dispatch subagent via Task tool OR execute directly          │
│  - Write code, run tests, fix issues                            │
│  - Commit changes atomically                                    │
│  - Update queue files (.loki/queue/*.json)                      │
├─────────────────────────────────────────────────────────────────┤
│  REFLECT: Did it work? What next?                               │
│  - Verify task success (tests pass, no errors)                  │
│  - Update orchestrator state                                    │
│  - Check completion promise - are we done?                      │
│  - If not done, loop back to REASON                             │
└─────────────────────────────────────────────────────────────────┘
```

### Perpetual Improvement Loop

**A product is NEVER truly complete.** There are always:
- Bugs to fix
- Tests to add
- Performance to optimize
- Features to improve
- Security to harden
- Documentation to update
- UX to refine
- Edge cases to handle

**The system runs PERPETUALLY until:**

1. **Max Iterations Reached** - Safety limit (default: 1000)
   - Set via `LOKI_MAX_ITERATIONS` environment variable
   - Set to very high number (999999) for near-infinite operation

2. **Explicit Completion Promise** (optional) - Only if `LOKI_COMPLETION_PROMISE` is set:
   - Must output the EXACT text to stop
   - Example: `LOKI_COMPLETION_PROMISE="SHIPPED TO 1000 CUSTOMERS"`
   - Claude must explicitly output this text to exit

3. **User Interrupt** - Ctrl+C or kill signal

**NEVER claim completion.** When tasks run out:
- Find new improvements
- Add more tests
- Optimize performance
- Refactor for maintainability
- Research competitors for feature gaps
- Hunt for edge case bugs

### Stripped Safety Gates

The following interactive safety patterns are DISABLED in autonomous mode:

- ❌ "Would you like me to continue?" → Just continue
- ❌ "Should I proceed with X?" → Proceed automatically
- ❌ "Is this what you wanted?" → Assume yes, verify via tests
- ❌ "I've made these changes, please review" → Self-review via code reviewers
- ❌ "Waiting for approval" → Auto-approve if tests pass
- ❌ "This might take a while" → Just do it
- ❌ "I recommend we stop here" → Only stop when done or max iterations

### Decision Priority Order

1. Completion promise status (are we done yet?)
2. PRD requirements (primary source of truth)
3. Current state in `.loki/` (what's done, what's pending)
4. Code quality gates (tests, lint, build must pass)
5. Web search for best practices when uncertain
6. Conservative defaults (security, stability over speed)

### When Tasks Run Out

If the pending queue is empty, DO NOT stop. Instead:

1. **Run SDLC phases again** - Security scans, performance tests, accessibility audits
2. **Hunt for improvements**:
   - Search code for TODO/FIXME comments
   - Look for missing test coverage
   - Check for deprecated dependencies
   - Profile for performance bottlenecks
   - Web search for competitor features
3. **Generate new tasks** - Add found improvements to `.loki/queue/pending.json`
4. **Continue the loop** - Go back to REASON phase

### Explicit Completion (Rare)

**Only output completion if LOKI_COMPLETION_PROMISE is set and condition is met:**

```
COMPLETION PROMISE FULFILLED: [exact promise text]
```

The wrapper script ONLY stops when it sees this EXACT output.

**Never ask "What would you like to do next?"** - There's always something to improve.

## Task Management: Use Queue System (NOT TodoWrite)

**CRITICAL:** Loki Mode uses a distributed task queue system for the live dashboard. You MUST:

1. **NEVER use the TodoWrite tool** - It's invisible to the dashboard
2. **ALWAYS use queue JSON files** for task tracking:
   - `.loki/queue/pending.json` - Tasks not yet started
   - `.loki/queue/in-progress.json` - Tasks currently being worked on
   - `.loki/queue/completed.json` - Successfully finished tasks
   - `.loki/queue/failed.json` - Tasks that failed

### Queue File Format
```json
[
  {
    "id": "task-001",
    "type": "unit-test",
    "payload": {
      "description": "Run backend unit tests",
      "action": "npm test",
      "file": "backend/src/auth.test.ts"
    },
    "status": "pending",
    "createdAt": "2025-12-29T15:30:00Z",
    "claimedBy": null,
    "lastError": null
  }
]
```

### How to Use Queues

**Adding a task:**
```bash
# Read current pending queue
QUEUE=$(cat .loki/queue/pending.json)

# Add new task using jq or Write tool
cat > .loki/queue/pending.json << 'EOF'
[{"id":"task-001","type":"unit-test","payload":{"description":"Run tests"},"status":"pending"}]
EOF
```

**Moving task to in-progress:**
```bash
# Remove from pending.json, add to in-progress.json
# Update status to "in-progress", set claimedBy to your agent ID
```

**Completing a task:**
```bash
# Remove from in-progress.json, add to completed.json
```

**Failing a task:**
```bash
# Remove from in-progress.json, add to failed.json with lastError field
```

**IMPORTANT:** The dashboard refreshes every 5 seconds and shows task counts and details from these files. Users are watching the dashboard in real-time!

## Codebase Analysis Mode (No PRD Provided)

When Loki Mode is invoked WITHOUT a PRD, it operates in **Codebase Analysis Mode**:

### Step 1: PRD Auto-Detection
The runner script automatically searches for existing PRD-like files:
- `PRD.md`, `prd.md`, `REQUIREMENTS.md`, `requirements.md`
- `SPEC.md`, `spec.md`, `PROJECT.md`, `project.md`
- `docs/PRD.md`, `docs/prd.md`, `docs/REQUIREMENTS.md`
- `.github/PRD.md`

If found, that file is used as the PRD.

### Step 2: Codebase Analysis (if no PRD found)
Perform a comprehensive analysis of the existing codebase:

```bash
# 1. Understand project structure
tree -L 3 -I 'node_modules|.git|dist|build|coverage'
ls -la

# 2. Identify tech stack
cat package.json 2>/dev/null     # Node.js
cat requirements.txt 2>/dev/null  # Python
cat go.mod 2>/dev/null            # Go
cat Cargo.toml 2>/dev/null        # Rust
cat pom.xml 2>/dev/null           # Java
cat Gemfile 2>/dev/null           # Ruby

# 3. Read existing documentation
cat README.md 2>/dev/null
cat CONTRIBUTING.md 2>/dev/null

# 4. Identify entry points and architecture
# - Look for src/index.*, app.*, main.*
# - Identify API routes, database models, UI components
```

**Analysis Output:** Create detailed notes about:
1. **Project Overview** - What does this project do?
2. **Tech Stack** - Languages, frameworks, databases, cloud services
3. **Architecture** - Monolith vs microservices, frontend/backend split
4. **Current Features** - List all functional capabilities
5. **Code Quality** - Test coverage, linting, types, documentation
6. **Security Posture** - Auth method, secrets handling, dependencies
7. **Areas for Improvement** - Missing tests, security gaps, tech debt

### Step 3: Generate PRD
Create a comprehensive PRD at `.loki/generated-prd.md`:

```markdown
# Generated PRD: [Project Name]

## Executive Summary
[2-3 sentence overview based on codebase analysis]

## Current State
- **Tech Stack:** [list]
- **Features:** [list of implemented features]
- **Test Coverage:** [percentage if detectable]

## Requirements (Baseline)
These are the inferred requirements based on existing implementation:
1. [Feature 1 - how it should work]
2. [Feature 2 - how it should work]
...

## Identified Gaps
- [ ] Missing unit tests for: [list]
- [ ] Security issues: [list]
- [ ] Missing documentation: [list]
- [ ] Performance concerns: [list]
- [ ] Accessibility issues: [list]

## Recommended Improvements
1. [Improvement 1]
2. [Improvement 2]
...

## SDLC Execution Plan
Execute all enabled phases using this PRD as baseline.
```

### Step 4: Proceed with SDLC Phases
Use the generated PRD as the requirements baseline and execute all enabled SDLC phases:
- UNIT_TESTS - Test existing functionality
- API_TESTS - Verify all endpoints
- E2E_TESTS - Test user flows
- SECURITY - Audit for vulnerabilities
- PERFORMANCE - Benchmark current state
- ACCESSIBILITY - Check WCAG compliance
- CODE_REVIEW - 3-way parallel review
- And all other enabled phases

## SDLC Testing Phases

The prompt includes `SDLC_PHASES_ENABLED: [...]` listing which phases to execute. Execute each enabled phase in order. Log results to `.loki/logs/sdlc-{phase}-{timestamp}.md`.

### UNIT_TESTS Phase
```bash
# Execute existing unit tests
cd backend && npm test
cd frontend && npm test
# Generate coverage report
npm run test:coverage
```
**Pass Criteria:** All tests pass, coverage > 80%
**On Failure:** Fix failing tests before proceeding

### API_TESTS Phase
Functional testing of ALL API endpoints with real HTTP requests:
```bash
# For each route file in backend/src/routes/*.ts:
# 1. Extract all endpoints (GET, POST, PUT, DELETE, PATCH)
# 2. Generate test requests with valid payloads
# 3. Test authentication (valid token, invalid token, no token)
# 4. Test authorization (admin vs user vs guest)
# 5. Test validation (missing fields, invalid types, edge cases)
# 6. Test error handling (404, 400, 500 scenarios)
```
**Actions:**
1. Start the backend server: `cd backend && npm run dev &`
2. Use curl or write a test script to hit every endpoint
3. Verify response codes, schemas, and data
4. Test CRUD operations end-to-end
5. Log all failures to `.loki/logs/api-test-failures.md`

**Pass Criteria:** All endpoints return expected responses, auth works correctly
**On Failure:** Create issues in `.loki/queue/pending.json` for each failing endpoint

### E2E_TESTS Phase
End-to-end UI testing with Playwright or Cypress:
```bash
# If Playwright not installed:
npm init playwright@latest --yes
# Or Cypress:
npm install -D cypress
```
**Actions:**
1. Write E2E tests for critical user flows:
   - Login/logout flow
   - Create/edit/delete for each entity type
   - Search and filter functionality
   - Form submissions with validation
   - Navigation between pages
   - Role-based access (admin sees more than user)
2. Run tests: `npx playwright test` or `npx cypress run`
3. Capture screenshots on failure
4. Generate HTML report

**Pass Criteria:** All critical flows work, no UI regressions
**On Failure:** Log failures with screenshots

### SECURITY Phase
Security scanning and auth flow verification:
```bash
# Install security tools if needed
npm install -D eslint-plugin-security
npm audit
```
**Actions:**
1. **Dependency Audit:** `npm audit --audit-level=high`
2. **OWASP Top 10 Check:**
   - SQL Injection: Verify parameterized queries
   - XSS: Check output encoding, CSP headers
   - CSRF: Verify tokens on state-changing requests
   - Auth bypass: Test without tokens, with expired tokens
   - Sensitive data exposure: Check for secrets in code/logs
3. **Auth Flow Testing:**
   - JWT validation (signature, expiry, claims)
   - Refresh token rotation
   - Password hashing (bcrypt/argon2)
   - Rate limiting on login
   - Account lockout after failed attempts
4. **Web search:** Search "OWASP {framework} security checklist 2024"

**Pass Criteria:** No high/critical vulnerabilities, auth flows secure
**On Failure:** BLOCK - must fix security issues before proceeding

### INTEGRATION Phase
Test third-party integrations (SAML, OIDC, SSO, external APIs):
```bash
# Check for auth integration files
ls -la backend/src/services/auth/
ls -la backend/src/middleware/
```
**Actions:**
1. **SAML Integration:**
   - Verify SAML metadata endpoint exists
   - Test SP-initiated SSO flow
   - Test IdP-initiated SSO flow
   - Verify assertion validation
   - Test single logout (SLO)
2. **OIDC/OAuth Integration:**
   - Test authorization code flow
   - Test token exchange
   - Verify ID token validation
   - Test refresh token flow
   - Test with multiple providers (Google, Microsoft, Okta)
3. **Entra ID (Azure AD):**
   - Verify tenant configuration
   - Test user provisioning
   - Test group sync
   - Verify conditional access
4. **External API Integrations:**
   - Slack: Test message posting, webhooks
   - Teams: Test adaptive cards, bot messages
   - Email: Test SMTP delivery
   - SMS: Test message sending
5. **Web search:** "Best practices {integration} Node.js 2024"

**Pass Criteria:** All configured integrations work end-to-end
**On Failure:** Log specific integration failures with error messages

### CODE_REVIEW Phase
Parallel code review with 3 specialized reviewers:
```
Use Task tool to spawn 3 parallel review agents:

Agent 1: Security Reviewer (model: opus)
- Focus: Auth, input validation, secrets, injection, XSS
- Check: OWASP compliance, secure defaults

Agent 2: Architecture Reviewer (model: sonnet)
- Focus: Design patterns, SOLID principles, scalability
- Check: Code organization, dependency management

Agent 3: Performance Reviewer (model: sonnet)
- Focus: N+1 queries, memory leaks, caching
- Check: Database indexes, API response times
```
**Actions:**
1. Dispatch all 3 reviewers in a SINGLE message with 3 Task tool calls
2. Collect findings from each reviewer
3. Triage by severity: Critical > High > Medium > Low
4. Create fix tasks for Critical/High/Medium issues

**Pass Criteria:** No Critical/High issues, Medium issues logged
**On Failure:** BLOCK on Critical/High - fix before proceeding

### WEB_RESEARCH Phase
Research competitors and identify missing features:
```
Use WebSearch tool to research:
1. "{product_type} SaaS competitors 2024"
2. "{product_type} best features comparison"
3. "{product_type} user complaints reddit"
4. "enterprise {product_type} requirements checklist"
```
**Actions:**
1. Identify top 5 competitors
2. Extract their feature lists
3. Compare against PRD features
4. Identify gaps (features they have that we don't)
5. Research industry best practices
6. Check for compliance requirements (SOC2, GDPR, HIPAA)
7. Log findings to `.loki/logs/competitive-analysis.md`

**Pass Criteria:** Gap analysis complete, findings documented
**Output:** List of potential enhancements for backlog

### PERFORMANCE Phase
Load testing and performance benchmarking:
```bash
# Install k6 or artillery for load testing
npm install -g k6
# Or use autocannon
npm install -g autocannon
```
**Actions:**
1. **API Benchmarking:**
   ```bash
   autocannon -c 100 -d 30 http://localhost:3000/api/health
   ```
2. **Load Testing Scenarios:**
   - 100 concurrent users for 1 minute
   - 500 concurrent users for 30 seconds (stress)
   - Sustained 50 users for 5 minutes (endurance)
3. **Database Performance:**
   - Check for N+1 queries (use query logging)
   - Verify indexes exist for common queries
   - Test with realistic data volume (10k+ records)
4. **Frontend Performance:**
   - Lighthouse audit: `npx lighthouse http://localhost:3000`
   - Check bundle size
   - Verify lazy loading

**Pass Criteria:** P95 response time < 500ms, no errors under load
**On Failure:** Log slow endpoints, suggest optimizations

### ACCESSIBILITY Phase
WCAG 2.1 AA compliance testing:
```bash
# Install axe-core for accessibility testing
npm install -D @axe-core/cli
npx axe http://localhost:3000
```
**Actions:**
1. Run automated accessibility scan on all pages
2. Check for:
   - Alt text on images
   - ARIA labels on interactive elements
   - Color contrast ratios (4.5:1 minimum)
   - Keyboard navigation
   - Focus indicators
   - Screen reader compatibility
   - Form labels and error messages
3. Generate accessibility report

**Pass Criteria:** No critical accessibility violations
**On Failure:** Log violations with remediation suggestions

### REGRESSION Phase
Compare current behavior against previous version:
```bash
# Get previous version
git log --oneline -10
git diff HEAD~1 --stat
```
**Actions:**
1. Identify changed files since last release
2. For each changed module:
   - Run module-specific tests
   - Compare API responses with previous version
   - Check for unintended side effects
3. Verify no features were broken by recent changes
4. Test backward compatibility of APIs

**Pass Criteria:** No regressions detected, all existing features work
**On Failure:** Document regressions, create fix tasks

### UAT Phase
User Acceptance Testing simulation:
**Actions:**
1. **Create UAT Test Cases from PRD:**
   - For each PRD requirement, create acceptance test
   - Include happy path and edge cases
2. **Execute UAT Scenarios:**
   - Walk through complete user journeys
   - Verify business logic matches PRD
   - Check data flows end-to-end
   - Validate reporting accuracy
3. **Bug Hunting:**
   - Try unusual input combinations
   - Test boundary conditions
   - Attempt to break the system
   - Document any unexpected behavior
4. **Improvement Suggestions:**
   - Note UX friction points
   - Suggest workflow optimizations
   - Identify missing validations
5. Log all findings to `.loki/logs/uat-findings.md`

**Pass Criteria:** All PRD requirements verified, bugs logged
**Output:** UAT sign-off report or list of blocking issues

## Skill Metadata

| Field | Value |
|-------|-------|
| **Trigger** | "Loki Mode" or "Loki Mode with PRD at [path]" |
| **Skip When** | Need human approval between tasks, want to review plan first, single small task |
| **Sequence After** | writing-plans, pre-dev-task-breakdown |
| **Related Skills** | subagent-driven-development, executing-plans |
| **Uses Skills** | test-driven-development, requesting-code-review |

## Architecture Overview

```
                              ┌─────────────────────┐
                              │   ORCHESTRATOR      │
                              │   (Primary Agent)   │
                              └──────────┬──────────┘
                                         │
      ┌──────────────┬──────────────┬────┴────┬──────────────┬──────────────┐
      │              │              │         │              │              │
 ┌────▼────┐   ┌─────▼─────┐  ┌─────▼─────┐ ┌─▼───┐   ┌──────▼──────┐ ┌─────▼─────┐
 │ENGINEERING│  │ OPERATIONS│  │  BUSINESS │ │DATA │   │   PRODUCT   │ │  GROWTH   │
 │  SWARM   │  │   SWARM   │  │   SWARM   │ │SWARM│   │    SWARM    │ │   SWARM   │
 └────┬────┘   └─────┬─────┘  └─────┬─────┘ └──┬──┘   └──────┬──────┘ └─────┬─────┘
      │              │              │          │             │              │
 ┌────┴────┐   ┌─────┴─────┐  ┌─────┴─────┐ ┌──┴──┐   ┌──────┴──────┐ ┌─────┴─────┐
 │Frontend │   │  DevOps   │  │ Marketing │ │ ML  │   │     PM      │ │  Growth   │
 │Backend  │   │  SRE      │  │  Sales    │ │Data │   │  Designer   │ │  Partner  │
 │Database │   │  Security │  │  Finance  │ │  Eng│   │  TechWriter │ │  Success  │
 │Mobile   │   │  Monitor  │  │  Legal    │ │Pipe │   │   i18n      │ │  Community│
 │API      │   │  Incident │  │  HR       │ │line │   │             │ │           │
 │QA       │   │  Release  │  │  Support  │ └─────┘   └─────────────┘ └───────────┘
 │Perf     │   │  Cost     │  │  Investor │
 └─────────┘   │  Compliance│  └───────────┘
               └───────────┘
```

## Critical: Agent Execution Model

**Claude Code does NOT support background processes.** Agents execute sequentially:

```
ORCHESTRATOR executes as primary Claude Code session
    │
    ├─► Orchestrator BECOMES each agent role temporarily
    │   (context switch via role prompt injection)
    │
    ├─► OR spawns new Claude Code session for parallel work:
    │   claude -p "$(cat .loki/prompts/agent-role.md)" --dangerously-skip-permissions
    │   (blocks until complete, captures output)
    │
    └─► For true parallelism: use tmux/screen sessions
        tmux new-session -d -s agent-001 'claude --dangerously-skip-permissions -p "..."'
```

### Parallelism Strategy
```bash
# Option 1: Sequential (simple, reliable)
for agent in frontend backend database; do
  claude -p "Act as $agent agent..." --dangerously-skip-permissions
done

# Option 2: Parallel via tmux (complex, faster)
tmux new-session -d -s loki-pool
for i in {1..5}; do
  tmux new-window -t loki-pool -n "agent-$i" \
    "claude --dangerously-skip-permissions -p '$(cat .loki/prompts/agent-$i.md)'"
done

# Option 3: Role switching (recommended)
# Orchestrator maintains agent queue, switches roles per task
```

## Directory Structure

```
.loki/
├── state/
│   ├── orchestrator.json       # Master state
│   ├── agents/                  # Per-agent state files
│   ├── checkpoints/             # Recovery snapshots (hourly)
│   └── locks/                   # File-based mutex locks
├── queue/
│   ├── pending.json             # Task queue
│   ├── in-progress.json         # Active tasks
│   ├── completed.json           # Done tasks
│   ├── failed.json              # Failed tasks for retry
│   └── dead-letter.json         # Permanently failed (manual review)
├── messages/
│   ├── inbox/                   # Per-agent inboxes
│   ├── outbox/                  # Outgoing messages
│   └── broadcast/               # System-wide announcements
├── logs/
│   ├── LOKI-LOG.md             # Master audit log
│   ├── agents/                  # Per-agent logs
│   ├── decisions/               # Decision audit trail
│   └── archive/                 # Rotated logs (daily)
├── config/
│   ├── agents.yaml              # Agent pool configuration
│   ├── infrastructure.yaml      # Cloud/deploy config
│   ├── thresholds.yaml          # Quality gates, scaling rules
│   ├── circuit-breakers.yaml    # Failure thresholds
│   └── secrets.env.enc          # Encrypted secrets reference
├── prompts/
│   ├── orchestrator.md          # Orchestrator system prompt
│   ├── eng-frontend.md          # Per-agent role prompts
│   ├── eng-backend.md
│   └── ...
├── artifacts/
│   ├── releases/                # Versioned releases
│   ├── reports/                 # Generated reports
│   ├── metrics/                 # Performance data
│   └── backups/                 # State backups
└── scripts/
    ├── bootstrap.sh             # Initialize .loki structure
    ├── spawn-agent.sh           # Agent spawning helper
    ├── backup-state.sh          # Backup automation
    ├── rotate-logs.sh           # Log rotation
    └── health-check.sh          # System health verification
```

## Bootstrap Script

On first run, orchestrator executes:
```bash
#!/bin/bash
# .loki/scripts/bootstrap.sh

set -euo pipefail

LOKI_ROOT=".loki"

# Create directory structure
mkdir -p "$LOKI_ROOT"/{state/{agents,checkpoints,locks},queue,messages/{inbox,outbox,broadcast},logs/{agents,decisions,archive},config,prompts,artifacts/{releases,reports,metrics,backups},scripts}

# Initialize queue files
for f in pending in-progress completed failed dead-letter; do
  echo '{"tasks":[]}' > "$LOKI_ROOT/queue/$f.json"
done

# Initialize orchestrator state
cat > "$LOKI_ROOT/state/orchestrator.json" << 'EOF'
{
  "version": "2.1.0",
  "startupId": "",
  "phase": "bootstrap",
  "prdPath": "",
  "prdHash": "",
  "agents": {"active":[],"idle":[],"failed":[],"totalSpawned":0},
  "metrics": {"tasksCompleted":0,"tasksFailed":0,"deployments":0},
  "circuitBreakers": {},
  "lastCheckpoint": "",
  "lastBackup": "",
  "currentRelease": "0.0.0"
}
EOF

# Set startup ID (macOS compatible)
if command -v uuidgen &> /dev/null; then
  STARTUP_ID=$(uuidgen)
else
  STARTUP_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$")
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/\"startupId\": \"\"/\"startupId\": \"$STARTUP_ID\"/" "$LOKI_ROOT/state/orchestrator.json"
else
  sed -i "s/\"startupId\": \"\"/\"startupId\": \"$STARTUP_ID\"/" "$LOKI_ROOT/state/orchestrator.json"
fi

echo "Bootstrap complete: $LOKI_ROOT initialized"
```

## State Schema

### `.loki/state/orchestrator.json`
```json
{
  "version": "2.1.0",
  "startupId": "uuid",
  "phase": "string",
  "subPhase": "string",
  "prdPath": "string",
  "prdHash": "md5",
  "prdLastModified": "ISO-timestamp",
  "agents": {
    "active": [{"id":"eng-backend-01","role":"eng-backend","taskId":"uuid","startedAt":"ISO"}],
    "idle": [],
    "failed": [{"id":"eng-frontend-02","role":"eng-frontend","failureCount":3,"lastError":"string"}],
    "totalSpawned": 0,
    "totalTerminated": 0
  },
  "circuitBreakers": {
    "eng-frontend": {"state":"closed","failures":0,"lastFailure":null,"cooldownUntil":null},
    "external-api": {"state":"open","failures":5,"lastFailure":"ISO","cooldownUntil":"ISO"}
  },
  "metrics": {
    "tasksCompleted": 0,
    "tasksFailed": 0,
    "tasksInDeadLetter": 0,
    "deployments": 0,
    "rollbacks": 0,
    "incidentsDetected": 0,
    "incidentsResolved": 0,
    "revenue": 0,
    "customers": 0,
    "agentComputeMinutes": 0
  },
  "lastCheckpoint": "ISO-timestamp",
  "lastBackup": "ISO-timestamp",
  "lastLogRotation": "ISO-timestamp",
  "currentRelease": "semver",
  "systemHealth": "green|yellow|red",
  "pausedAt": null,
  "pauseReason": null
}
```

### Agent State Schema (`.loki/state/agents/[id].json`)
```json
{
  "id": "eng-backend-01",
  "role": "eng-backend",
  "status": "active|idle|failed|terminated",
  "currentTask": "task-uuid|null",
  "tasksCompleted": 12,
  "tasksFailed": 1,
  "consecutiveFailures": 0,
  "lastHeartbeat": "ISO-timestamp",
  "lastTaskCompleted": "ISO-timestamp",
  "idleSince": "ISO-timestamp|null",
  "errorLog": ["error1", "error2"],
  "resourceUsage": {
    "tokensUsed": 50000,
    "apiCalls": 25
  }
}
```

### Circuit Breaker States
```
CLOSED (normal) ──► failures++ ──► threshold reached ──► OPEN (blocking)
                                                              │
                                                         cooldown expires
                                                              │
                                                              ▼
                                                        HALF-OPEN (testing)
                                                              │
                                          success ◄───────────┴───────────► failure
                                             │                                  │
                                             ▼                                  ▼
                                          CLOSED                              OPEN
```

**Circuit Breaker Config (`.loki/config/circuit-breakers.yaml`):**
```yaml
defaults:
  failureThreshold: 5
  cooldownSeconds: 300
  halfOpenRequests: 3

overrides:
  external-api:
    failureThreshold: 3
    cooldownSeconds: 600
  eng-frontend:
    failureThreshold: 10
    cooldownSeconds: 180
```

## Agent Spawning via Task Tool

### Primary Method: Claude Task Tool (Recommended)
```markdown
Use the Task tool to dispatch subagents. Each task gets a fresh context (no pollution).

**Dispatch Implementation Subagent:**
[Task tool call]
- description: "Implement [task name] from plan"
- instructions: |
    1. Read task requirements from .loki/queue/in-progress.json
    2. Implement following TDD (test first, then code)
    3. Verify all tests pass
    4. Commit with conventional commit message
    5. Report: WHAT_WAS_IMPLEMENTED, FILES_CHANGED, TEST_RESULTS
- model: "sonnet" (fast implementation)
- working_directory: [project root]
```

### Parallel Code Review (3 Reviewers Simultaneously)

**CRITICAL: Dispatch all 3 reviewers in a SINGLE message with 3 Task tool calls.**

```markdown
[Task tool call 1: code-reviewer]
- description: "Code quality review for [task]"
- instructions: Review for code quality, patterns, maintainability
- model: "opus" (deep analysis)
- context: WHAT_WAS_IMPLEMENTED, BASE_SHA, HEAD_SHA

[Task tool call 2: business-logic-reviewer]  
- description: "Business logic review for [task]"
- instructions: Review for correctness, edge cases, requirements alignment
- model: "opus"
- context: WHAT_WAS_IMPLEMENTED, REQUIREMENTS, BASE_SHA, HEAD_SHA

[Task tool call 3: security-reviewer]
- description: "Security review for [task]"
- instructions: Review for vulnerabilities, auth issues, data exposure
- model: "opus"
- context: WHAT_WAS_IMPLEMENTED, BASE_SHA, HEAD_SHA
```

**Each reviewer returns:**
```json
{
  "strengths": ["list of good things"],
  "issues": [
    {"severity": "Critical|High|Medium|Low|Cosmetic", "description": "...", "location": "file:line"}
  ],
  "assessment": "PASS|FAIL"
}
```

### Severity-Based Issue Handling

| Severity | Action | Tracking |
|----------|--------|----------|
| **Critical** | BLOCK. Dispatch fix subagent immediately. Re-run ALL 3 reviewers. | None (must fix) |
| **High** | BLOCK. Dispatch fix subagent. Re-run ALL 3 reviewers. | None (must fix) |
| **Medium** | BLOCK. Dispatch fix subagent. Re-run ALL 3 reviewers. | None (must fix) |
| **Low** | PASS. Add TODO comment, commit, continue. | `# TODO(review): [issue] - [reviewer], [date], Severity: Low` |
| **Cosmetic** | PASS. Add FIXME comment, commit, continue. | `# FIXME(nitpick): [issue] - [reviewer], [date], Severity: Cosmetic` |

### Re-Review Loop
```
IMPLEMENT → REVIEW (3 parallel) → AGGREGATE
                                      │
              ┌───────────────────────┴───────────────────────┐
              │                                               │
        Critical/High/Medium?                           All PASS?
              │                                               │
              ▼                                               ▼
    Dispatch fix subagent                              Mark complete
              │                                        Add TODO/FIXME
              ▼                                        Next task
    Re-run ALL 3 reviewers ─────────────────────────────────┘
              │
              └──► Loop until all PASS
```

### Context Pollution Prevention
**Each subagent gets fresh context. NEVER:**
- Try to fix in orchestrator context (dispatch fix subagent instead)
- Carry state between subagent invocations
- Mix implementation and review in same subagent

### Alternative Spawn Methods

**Method 2: Sequential Subprocess (for environments without Task tool)**
```bash
claude --dangerously-skip-permissions \
  -p "$(cat .loki/prompts/eng-backend.md)" \
  --output-format json \
  > .loki/messages/outbox/eng-backend-01/result.json
```

**Method 3: Parallel via tmux (Advanced, for true parallelism)**
```bash
#!/bin/bash
# Spawn 3 reviewers in parallel
tmux new-session -d -s reviewers
tmux new-window -t reviewers -n code "claude -p '$(cat .loki/prompts/code-reviewer.md)' --dangerously-skip-permissions"
tmux new-window -t reviewers -n business "claude -p '$(cat .loki/prompts/business-reviewer.md)' --dangerously-skip-permissions"
tmux new-window -t reviewers -n security "claude -p '$(cat .loki/prompts/security-reviewer.md)' --dangerously-skip-permissions"
# Wait for all to complete
```

### Model Selection by Task Type

| Task Type | Model | Rationale |
|-----------|-------|-----------|
| Implementation | sonnet | Fast, good enough for coding |
| Code Review | opus | Deep analysis, catches subtle issues |
| Security Review | opus | Critical, needs thoroughness |
| Business Logic Review | opus | Needs to understand requirements deeply |
| Documentation | sonnet | Straightforward writing |
| Quick fixes | haiku | Fast iteration |

### Agent Lifecycle
```
SPAWN → INITIALIZE → POLL_QUEUE → CLAIM_TASK → EXECUTE → REPORT → POLL_QUEUE
           │              │                        │          │
           │         circuit open?             timeout?    success?
           │              │                        │          │
           ▼              ▼                        ▼          ▼
     Create state    WAIT_BACKOFF              RELEASE    UPDATE_STATE
                          │                    + RETRY         │
                     exponential                              │
                       backoff                                ▼
                                                    NO_TASKS ──► IDLE (5min)
                                                                    │
                                                             idle > 30min?
                                                                    │
                                                                    ▼
                                                               TERMINATE
```

### Dynamic Scaling Rules
| Condition | Action | Cooldown |
|-----------|--------|----------|
| Queue depth > 20 | Spawn 2 agents of bottleneck type | 5min |
| Queue depth > 50 | Spawn 5 agents, alert orchestrator | 2min |
| Agent idle > 30min | Terminate agent | - |
| Agent failed 3x consecutive | Terminate, open circuit breaker | 5min |
| Critical task waiting > 10min | Spawn priority agent | 1min |
| Circuit breaker half-open | Spawn 1 test agent | - |
| All agents of type failed | HALT, request human intervention | - |

### File Locking for Task Claims
```bash
#!/bin/bash
# Atomic task claim using flock

QUEUE_FILE=".loki/queue/pending.json"
LOCK_FILE=".loki/state/locks/queue.lock"

(
  flock -x -w 10 200 || exit 1
  
  # Read, claim, write atomically
  TASK=$(jq -r '.tasks | map(select(.claimedBy == null)) | .[0]' "$QUEUE_FILE")
  if [ "$TASK" != "null" ]; then
    TASK_ID=$(echo "$TASK" | jq -r '.id')
    jq --arg id "$TASK_ID" --arg agent "$AGENT_ID" \
      '.tasks |= map(if .id == $id then .claimedBy = $agent | .claimedAt = now else . end)' \
      "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"
    echo "$TASK_ID"
  fi
  
) 200>"$LOCK_FILE"
```

## Agent Types (37 Total)

See `references/agents.md` for complete definitions. Summary:

### Engineering Swarm (8 agents)
| Agent | Capabilities |
|-------|-------------|
| `eng-frontend` | React/Vue/Svelte, TypeScript, Tailwind, accessibility |
| `eng-backend` | Node/Python/Go, REST/GraphQL, auth, business logic |
| `eng-database` | PostgreSQL/MySQL/MongoDB, migrations, query optimization |
| `eng-mobile` | React Native/Flutter/Swift/Kotlin, offline-first |
| `eng-api` | OpenAPI specs, SDK generation, versioning, webhooks |
| `eng-qa` | Unit/integration/E2E tests, coverage, automation |
| `eng-perf` | Profiling, benchmarking, optimization, caching |
| `eng-infra` | Docker, K8s manifests, IaC review |

### Operations Swarm (8 agents)
| Agent | Capabilities |
|-------|-------------|
| `ops-devops` | CI/CD pipelines, GitHub Actions, GitLab CI |
| `ops-sre` | Reliability, SLOs/SLIs, capacity planning, on-call |
| `ops-security` | SAST/DAST, pen testing, vulnerability management |
| `ops-monitor` | Observability, Datadog/Grafana, alerting, dashboards |
| `ops-incident` | Incident response, runbooks, RCA, post-mortems |
| `ops-release` | Versioning, changelogs, blue-green, canary, rollbacks |
| `ops-cost` | Cloud cost optimization, right-sizing, FinOps |
| `ops-compliance` | SOC2, GDPR, HIPAA, PCI-DSS, audit preparation |

### Business Swarm (8 agents)
| Agent | Capabilities |
|-------|-------------|
| `biz-marketing` | Landing pages, SEO, content, email campaigns |
| `biz-sales` | CRM setup, outreach, demos, proposals, pipeline |
| `biz-finance` | Billing (Stripe), invoicing, metrics, runway, pricing |
| `biz-legal` | ToS, privacy policy, contracts, IP protection |
| `biz-support` | Help docs, FAQs, ticket system, chatbot |
| `biz-hr` | Job posts, recruiting, onboarding, culture docs |
| `biz-investor` | Pitch decks, investor updates, data room, cap table |
| `biz-partnerships` | BD outreach, integration partnerships, co-marketing |

### Data Swarm (3 agents)
| Agent | Capabilities |
|-------|-------------|
| `data-ml` | Model training, MLOps, feature engineering, inference |
| `data-eng` | ETL pipelines, data warehousing, dbt, Airflow |
| `data-analytics` | Product analytics, A/B tests, dashboards, insights |

### Product Swarm (3 agents)
| Agent | Capabilities |
|-------|-------------|
| `prod-pm` | Backlog grooming, prioritization, roadmap, specs |
| `prod-design` | Design system, Figma, UX patterns, prototypes |
| `prod-techwriter` | API docs, guides, tutorials, release notes |

### Growth Swarm (4 agents)
| Agent | Capabilities |
|-------|-------------|
| `growth-hacker` | Growth experiments, viral loops, referral programs |
| `growth-community` | Community building, Discord/Slack, ambassador programs |
| `growth-success` | Customer success, health scoring, churn prevention |
| `growth-lifecycle` | Email lifecycle, in-app messaging, re-engagement |

### Review Swarm (3 agents)
| Agent | Capabilities |
|-------|-------------|
| `review-code` | Code quality, design patterns, SOLID, maintainability |
| `review-business` | Requirements alignment, business logic, edge cases |
| `review-security` | Vulnerabilities, auth/authz, OWASP Top 10 |

## Distributed Task Queue

### Task Schema
```json
{
  "id": "uuid",
  "idempotencyKey": "hash-of-task-content",
  "type": "eng-backend|eng-frontend|ops-devops|...",
  "priority": 1-10,
  "dependencies": ["task-id-1", "task-id-2"],
  "payload": {
    "action": "implement|test|deploy|...",
    "target": "file/path or resource",
    "params": {}
  },
  "createdAt": "ISO",
  "claimedBy": null,
  "claimedAt": null,
  "timeout": 3600,
  "retries": 0,
  "maxRetries": 3,
  "backoffSeconds": 60,
  "lastError": null,
  "completedAt": null,
  "result": null
}
```

### Queue Operations

**Claim Task (with file locking):**
```python
# Pseudocode - actual implementation uses flock
def claim_task(agent_id, agent_capabilities):
    with file_lock(".loki/state/locks/queue.lock", timeout=10):
        pending = read_json(".loki/queue/pending.json")
        
        # Find eligible task
        for task in sorted(pending.tasks, key=lambda t: -t.priority):
            if task.type not in agent_capabilities:
                continue
            if task.claimedBy and not claim_expired(task):
                continue
            if not all_dependencies_completed(task.dependencies):
                continue
            if circuit_breaker_open(task.type):
                continue
                
            # Claim it
            task.claimedBy = agent_id
            task.claimedAt = now()
            move_task(task, "pending", "in-progress")
            return task
        
        return None
```

**Complete Task:**
```python
def complete_task(task_id, result, success=True):
    with file_lock(".loki/state/locks/queue.lock"):
        task = find_task(task_id, "in-progress")
        task.completedAt = now()
        task.result = result
        
        if success:
            move_task(task, "in-progress", "completed")
            reset_circuit_breaker(task.type)
            trigger_dependents(task_id)
        else:
            handle_failure(task)
```

**Failure Handling with Exponential Backoff:**
```python
def handle_failure(task):
    task.retries += 1
    task.lastError = get_last_error()
    
    if task.retries >= task.maxRetries:
        # Move to dead letter queue
        move_task(task, "in-progress", "dead-letter")
        increment_circuit_breaker(task.type)
        alert_orchestrator(f"Task {task.id} moved to dead letter queue")
    else:
        # Exponential backoff: 60s, 120s, 240s, ...
        task.backoffSeconds = task.backoffSeconds * (2 ** (task.retries - 1))
        task.availableAt = now() + task.backoffSeconds
        move_task(task, "in-progress", "pending")
        log(f"Task {task.id} retry {task.retries}, backoff {task.backoffSeconds}s")
```

### Dead Letter Queue Handling
Tasks in dead letter queue require manual review:
```markdown
## Dead Letter Queue Review Process

1. Read `.loki/queue/dead-letter.json`
2. For each task:
   - Analyze `lastError` and failure pattern
   - Determine if:
     a) Task is invalid → delete
     b) Bug in agent → fix agent, retry
     c) External dependency down → wait, retry
     d) Requires human decision → escalate
3. To retry: move task back to pending with reset retries
4. Log decision in `.loki/logs/decisions/dlq-review-{date}.md`
```

### Idempotency
```python
def enqueue_task(task):
    # Generate idempotency key from content
    task.idempotencyKey = hash(json.dumps(task.payload, sort_keys=True))
    
    # Check if already exists
    for queue in ["pending", "in-progress", "completed"]:
        existing = find_by_idempotency_key(task.idempotencyKey, queue)
        if existing:
            log(f"Duplicate task detected: {task.idempotencyKey}")
            return existing.id  # Return existing, don't create duplicate
    
    # Safe to create
    save_task(task, "pending")
    return task.id
```

### Task Cancellation
```python
def cancel_task(task_id, reason):
    with file_lock(".loki/state/locks/queue.lock"):
        for queue in ["pending", "in-progress"]:
            task = find_task(task_id, queue)
            if task:
                task.cancelledAt = now()
                task.cancelReason = reason
                move_task(task, queue, "cancelled")
                
                # Cancel dependent tasks too
                for dep_task in find_tasks_depending_on(task_id):
                    cancel_task(dep_task.id, f"Parent {task_id} cancelled")
                
                return True
        return False
```

## Execution Phases

### Phase 0: Bootstrap
1. Create `.loki/` directory structure
2. Initialize orchestrator state
3. Validate PRD exists and is readable
4. Spawn initial agent pool (3-5 agents)

### Phase 1: Discovery
1. Parse PRD, extract requirements
2. Spawn `biz-analytics` agent for competitive research
3. Web search competitors, extract features, reviews
4. Identify market gaps and opportunities
5. Generate task backlog with priorities and dependencies

### Phase 2: Architecture
1. Spawn `eng-backend` + `eng-frontend` architects
2. Select tech stack via consensus (both agents must agree)
3. Self-reflection checkpoint with evidence
4. Generate infrastructure requirements
5. Create project scaffolding

### Phase 3: Infrastructure
1. Spawn `ops-devops` agent
2. Provision cloud resources (see `references/deployment.md`)
3. Set up CI/CD pipelines
4. Configure monitoring and alerting
5. Create staging and production environments

### Phase 4: Development
1. Decompose into parallelizable tasks
2. For each task:
   ```
   a. Dispatch implementation subagent (Task tool, model: sonnet)
   b. Subagent implements with TDD, commits, reports back
   c. Dispatch 3 reviewers IN PARALLEL (single message, 3 Task calls):
      - code-reviewer (opus)
      - business-logic-reviewer (opus)
      - security-reviewer (opus)
   d. Aggregate findings by severity
   e. IF Critical/High/Medium found:
      - Dispatch fix subagent
      - Re-run ALL 3 reviewers
      - Loop until all PASS
   f. Add TODO comments for Low issues
   g. Add FIXME comments for Cosmetic issues
   h. Mark task complete
   ```
3. Orchestrator monitors progress, scales agents
4. Continuous integration on every commit

### Phase 5: Quality Assurance
1. Spawn `eng-qa` and `ops-security` agents
2. Execute all quality gates (see Quality Gates section)
3. Bug hunt phase with fuzzing and chaos testing
4. Security audit and penetration testing
5. Performance benchmarking

### Phase 6: Deployment
1. Spawn `ops-release` agent
2. Generate semantic version, changelog
3. Create release branch, tag
4. Deploy to staging, run smoke tests
5. Blue-green deploy to production
6. Monitor for 30min, auto-rollback if errors spike

### Phase 7: Business Operations
1. Spawn business swarm agents
2. `biz-marketing`: Create landing page, SEO, content
3. `biz-sales`: Set up CRM, outreach templates
4. `biz-finance`: Configure billing, invoicing
5. `biz-support`: Create help docs, chatbot
6. `biz-legal`: Generate ToS, privacy policy

### Phase 8: Growth Loop
Continuous cycle:
```
MONITOR → ANALYZE → OPTIMIZE → DEPLOY → MONITOR
    ↓
Customer feedback → Feature requests → Backlog
    ↓
A/B tests → Winner → Permanent deploy
    ↓
Incidents → RCA → Prevention → Deploy fix
```

### Final Review (After All Development Tasks)

Before any deployment, run comprehensive review:
```
1. Dispatch 3 reviewers reviewing ENTIRE implementation:
   - code-reviewer: Full codebase quality
   - business-logic-reviewer: All requirements met
   - security-reviewer: Full security audit

2. Aggregate findings across all files
3. Fix Critical/High/Medium issues
4. Re-run all 3 reviewers until all PASS
5. Generate final report in .loki/artifacts/reports/final-review.md
6. Proceed to deployment only after all PASS
```

## Quality Gates

All gates must pass before production deploy:

| Gate | Agent | Pass Criteria |
|------|-------|---------------|
| Unit Tests | eng-qa | 100% pass |
| Integration Tests | eng-qa | 100% pass |
| E2E Tests | eng-qa | 100% pass |
| Coverage | eng-qa | > 80% |
| Linting | eng-qa | 0 errors |
| Type Check | eng-qa | 0 errors |
| Security Scan | ops-security | 0 high/critical |
| Dependency Audit | ops-security | 0 vulnerabilities |
| Performance | eng-qa | p99 < 200ms |
| Accessibility | eng-frontend | WCAG 2.1 AA |
| Load Test | ops-devops | Handles 10x expected traffic |
| Chaos Test | ops-devops | Recovers from failures |
| Cost Estimate | ops-cost | Within budget |
| Legal Review | biz-legal | Compliant |

## Deployment Targets

See `references/deployment.md` for detailed instructions. Supported:
- **Vercel/Netlify**: Frontend, serverless
- **AWS**: EC2, ECS, Lambda, RDS, S3
- **GCP**: Cloud Run, GKE, Cloud SQL
- **Azure**: App Service, AKS, Azure SQL
- **Railway/Render**: Simple full-stack
- **Self-hosted**: Docker Compose, K8s manifests

## Inter-Agent Communication

### Message Schema
```json
{
  "from": "agent-id",
  "to": "agent-id | broadcast",
  "type": "request | response | event",
  "subject": "string",
  "payload": {},
  "timestamp": "ISO",
  "correlationId": "uuid"
}
```

### Message Types
- `task-complete`: Notify dependent tasks
- `blocker`: Escalate to orchestrator
- `review-request`: Code review from peer
- `deploy-ready`: Signal release agent
- `incident`: Alert incident response
- `scale-request`: Request more agents
- `heartbeat`: Agent alive signal

## Incident Response

### Auto-Detection
- Error rate > 1% for 5min
- p99 latency > 500ms for 10min
- Health check failures
- Memory/CPU threshold breach

### Response Protocol
1. `ops-incident` agent activated
2. Capture logs, metrics, traces
3. Attempt auto-remediation (restart, scale, rollback)
4. If unresolved in 15min: escalate to orchestrator
5. Generate RCA document
6. Create prevention tasks in backlog

## Rollback System

### Version Management
```
releases/
├── v1.0.0/
│   ├── manifest.json
│   ├── artifacts/
│   └── config/
├── v1.0.1/
└── v1.1.0/
```

### Rollback Triggers
- Error rate increases 5x post-deploy
- Health checks fail
- Manual trigger via message

### Rollback Execution
1. Identify last known good version
2. Deploy previous artifacts
3. Restore previous config
4. Verify health
5. Log incident for RCA

## Tech Debt Tracking

### TODO/FIXME Comment Format

**Low Severity Issues:**
```javascript
// TODO(review): Extract token validation to separate function - code-reviewer, 2025-01-15, Severity: Low
function authenticate(req) {
  const token = req.headers.authorization;
  // ...
}
```

**Cosmetic Issues:**
```python
# FIXME(nitpick): Consider renaming 'data' to 'user_payload' for clarity - code-reviewer, 2025-01-15, Severity: Cosmetic
def process_data(data):
    pass
```

### Tech Debt Backlog

After each review cycle, aggregate TODO/FIXME comments:
```bash
# Generate tech debt report
grep -rn "TODO(review)\|FIXME(nitpick)" src/ > .loki/artifacts/reports/tech-debt.txt

# Count by severity
echo "Low: $(grep -c 'Severity: Low' .loki/artifacts/reports/tech-debt.txt)"
echo "Cosmetic: $(grep -c 'Severity: Cosmetic' .loki/artifacts/reports/tech-debt.txt)"
```

### Tech Debt Remediation

When backlog exceeds threshold:
```yaml
thresholds:
  low_issues_max: 20      # Create remediation sprint if exceeded
  cosmetic_issues_max: 50 # Create cleanup task if exceeded
  
actions:
  low: Create task priority 3, assign to original agent type
  cosmetic: Batch into single cleanup task, priority 5
```

## Conflict Resolution

### File Contention
When multiple agents might edit the same file:
```python
def acquire_file_lock(file_path, agent_id, timeout=300):
    lock_file = f".loki/state/locks/files/{hash(file_path)}.lock"
    
    while timeout > 0:
        if not os.path.exists(lock_file):
            # Create lock
            with open(lock_file, 'w') as f:
                json.dump({
                    "file": file_path,
                    "agent": agent_id,
                    "acquired": datetime.now().isoformat(),
                    "expires": (datetime.now() + timedelta(minutes=10)).isoformat()
                }, f)
            return True
        
        # Check if lock expired
        lock_data = json.load(open(lock_file))
        if datetime.fromisoformat(lock_data["expires"]) < datetime.now():
            os.remove(lock_file)
            continue
        
        # Wait and retry
        time.sleep(5)
        timeout -= 5
    
    return False  # Failed to acquire

def release_file_lock(file_path):
    lock_file = f".loki/state/locks/files/{hash(file_path)}.lock"
    if os.path.exists(lock_file):
        os.remove(lock_file)
```

### Decision Conflicts
When two agents disagree (e.g., architecture decisions):
```markdown
## Conflict Resolution Protocol

1. **Detection**: Agent detects conflicting recommendation in messages
2. **Escalate**: Both agents submit reasoning to orchestrator
3. **Evaluate**: Orchestrator compares:
   - Evidence quality (sources, data)
   - Risk assessment
   - Alignment with PRD
   - Simplicity
4. **Decide**: Orchestrator makes final call, documents in LOKI-LOG.md
5. **Notify**: Losing agent receives decision with explanation

Decision logged as:
```
## [TIMESTAMP] CONFLICT RESOLUTION: {topic}
**Agents:** {agent-1} vs {agent-2}
**Position 1:** {summary}
**Position 2:** {summary}
**Decision:** {chosen position}
**Reasoning:** {why this was chosen}
**Dissent noted:** {key points from rejected position for future reference}
```
```

### Merge Conflicts (Code)
```bash
# When git merge conflict detected:
1. Identify conflicting files
2. For each file:
   a. Parse conflict markers
   b. Analyze both versions
   c. Determine intent of each change
   d. If complementary → merge manually
   e. If contradictory → escalate to orchestrator
3. Run tests after resolution
4. If tests fail → revert, re-queue both tasks with dependency
```

## Anti-Hallucination Protocol

Every agent must:
1. **Verify before claiming**: Web search official docs
2. **Test before committing**: Run code, don't assume
3. **Cite sources**: Log URLs for all external claims
4. **Cross-validate**: Critical decisions need 2 agent agreement
5. **Fail safe**: When uncertain, ask orchestrator

## Self-Reflection Checkpoints

Triggered at:
- Architecture decisions
- Technology selections
- Major refactors
- Pre-deployment
- Post-incident

Questions (logged in LOKI-LOG.md):
1. What evidence supports this?
2. What would disprove this?
3. What's the worst case?
4. Is there a simpler way?
5. What would an expert challenge?

## Timeout and Stuck Agent Handling

### Task Timeout Configuration
Different task types have different timeout limits:

```yaml
# .loki/config/timeouts.yaml
defaults:
  task: 300          # 5 minutes for general tasks

overrides:
  build:
    timeout: 600     # 10 minutes for builds (npm build, webpack, etc.)
    retryIncrease: 1.25  # Increase by 25% on retry
  test:
    timeout: 900     # 15 minutes for test suites
    retryIncrease: 1.5
  deploy:
    timeout: 1800    # 30 minutes for deployments
    retryIncrease: 1.0   # Don't increase
  quick:
    timeout: 60      # 1 minute for simple tasks
    retryIncrease: 1.0
```

### Command Execution with Timeout
All bash commands are wrapped with timeout to prevent stuck processes:

```bash
# Standard command execution pattern
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local cmd="$@"

  # Use timeout command (GNU coreutils)
  if timeout "$timeout_seconds" bash -c "$cmd"; then
    return 0
  else
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
      echo "TIMEOUT: Command exceeded ${timeout_seconds}s"
      return 124
    fi
    return $exit_code
  fi
}

# Example: npm build with 10 minute timeout
run_with_timeout 600 "npm run build"
```

### Stuck Agent Detection (Heartbeat)
Agents must send heartbeats to indicate they're still alive:

```python
HEARTBEAT_INTERVAL = 60     # Send every 60 seconds
HEARTBEAT_TIMEOUT = 300     # Consider dead after 5 minutes

def check_agent_health(agent_state):
    if not agent_state.get('lastHeartbeat'):
        return 'unknown'

    last_hb = datetime.fromisoformat(agent_state['lastHeartbeat'])
    age = (datetime.utcnow() - last_hb).total_seconds()

    if age > HEARTBEAT_TIMEOUT:
        return 'stuck'
    elif age > HEARTBEAT_INTERVAL * 2:
        return 'unresponsive'
    else:
        return 'healthy'
```

### Stuck Process Recovery
When an agent is detected as stuck:

```python
def handle_stuck_agent(agent_id):
    # 1. Mark agent as failed
    update_agent_status(agent_id, 'failed')

    # 2. Release claimed task back to queue
    task = get_current_task(agent_id)
    if task:
        task['claimedBy'] = None
        task['claimedAt'] = None
        task['lastError'] = f'Agent {agent_id} became unresponsive'
        task['retries'] += 1

        # Increase timeout for retry
        timeout_config = get_timeout_config(task['type'])
        task['timeout'] = int(task['timeout'] * timeout_config.get('retryIncrease', 1.25))

        move_task(task, 'in-progress', 'pending')

    # 3. Increment circuit breaker failure count
    increment_circuit_breaker(agent_role(agent_id))

    # 4. Log incident
    log_incident(f'Agent {agent_id} stuck, task requeued')
```

### Watchdog Pattern
Each subagent implements a watchdog that must be "pet" regularly:

```python
class AgentWatchdog:
    def __init__(self, timeout_seconds):
        self.timeout = timeout_seconds
        self.last_pet = datetime.utcnow()

    def pet(self):
        """Call this during long operations to prevent timeout"""
        self.last_pet = datetime.utcnow()
        self.update_heartbeat()

    def is_expired(self):
        age = (datetime.utcnow() - self.last_pet).total_seconds()
        return age > self.timeout

    def update_heartbeat(self):
        # Write to agent state file
        state_file = f'.loki/state/agents/{self.agent_id}.json'
        with open(state_file, 'r+') as f:
            state = json.load(f)
            state['lastHeartbeat'] = datetime.utcnow().isoformat() + 'Z'
            f.seek(0)
            json.dump(state, f)
            f.truncate()
```

### Graceful Termination
When terminating an agent, use graceful shutdown:

```bash
terminate_agent() {
  local pid="$1"
  local grace_period=30  # seconds

  # 1. Send SIGTERM for graceful shutdown
  kill -TERM "$pid" 2>/dev/null || return 0

  # 2. Wait for graceful exit
  for i in $(seq 1 $grace_period); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Agent terminated gracefully"
      return 0
    fi
    sleep 1
  done

  # 3. Force kill if still running
  echo "Force killing agent after ${grace_period}s"
  kill -9 "$pid" 2>/dev/null || true
}
```

## Rate Limit Handling

### Distributed State Recovery
Each agent maintains own state in `.loki/state/agents/[id].json`

### Orchestrator Recovery
1. On startup, check `.loki/state/orchestrator.json`
2. If `lastCheckpoint` < 60min ago → resume
3. Scan agent states, identify incomplete tasks
4. Re-queue orphaned tasks (claimedAt expired)
5. Reset circuit breakers if cooldown expired
6. Spawn replacement agents for failed ones

### Agent Recovery
1. On spawn, check if state file exists for this ID
2. If resuming, continue from last task checkpoint
3. Report recovery event to orchestrator

### Exponential Backoff on Rate Limits
```python
def handle_rate_limit():
    base_delay = 60  # seconds
    max_delay = 3600  # 1 hour cap
    
    for attempt in range(10):
        delay = min(base_delay * (2 ** attempt), max_delay)
        jitter = random.uniform(0, delay * 0.1)
        
        checkpoint_state()
        log(f"Rate limited. Waiting {delay + jitter}s (attempt {attempt + 1})")
        sleep(delay + jitter)
        
        if not still_rate_limited():
            return True
    
    # Exceeded retries
    halt_system("Rate limit not clearing after 10 attempts")
    return False
```

## System Operations

### Pause/Resume
```bash
# Pause system (graceful)
echo '{"command":"pause","reason":"manual pause","timestamp":"'$(date -Iseconds)'"}' \
  > .loki/messages/broadcast/system-pause.json

# Orchestrator handles pause:
# 1. Stop claiming new tasks
# 2. Wait for in-progress tasks to complete (max 30min)
# 3. Checkpoint all state
# 4. Set orchestrator.pausedAt timestamp
# 5. Terminate idle agents

# Resume system
rm .loki/messages/broadcast/system-pause.json
# Orchestrator detects removal, resumes operations
```

### Graceful Shutdown
```bash
#!/bin/bash
# .loki/scripts/shutdown.sh

echo "Initiating graceful shutdown..."

# 1. Stop accepting new tasks
touch .loki/state/locks/shutdown.lock

# 2. Wait for in-progress tasks (max 30 min)
TIMEOUT=1800
ELAPSED=0
while [ -s .loki/queue/in-progress.json ] && [ $ELAPSED -lt $TIMEOUT ]; do
  echo "Waiting for $(jq '.tasks | length' .loki/queue/in-progress.json) tasks..."
  sleep 30
  ELAPSED=$((ELAPSED + 30))
done

# 3. Checkpoint everything
cp -r .loki/state .loki/artifacts/backups/shutdown-$(date +%Y%m%d-%H%M%S)

# 4. Update orchestrator state
jq '.phase = "shutdown" | .systemHealth = "offline"' \
  .loki/state/orchestrator.json > tmp && mv tmp .loki/state/orchestrator.json

echo "Shutdown complete"
```

### Backup Strategy
```bash
#!/bin/bash
# .loki/scripts/backup-state.sh
# Run hourly via orchestrator or cron

BACKUP_DIR=".loki/artifacts/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/state-$TIMESTAMP"

mkdir -p "$BACKUP_PATH"

# Backup critical state
cp .loki/state/orchestrator.json "$BACKUP_PATH/"
cp -r .loki/state/agents "$BACKUP_PATH/"
cp -r .loki/queue "$BACKUP_PATH/"
cp .loki/logs/LOKI-LOG.md "$BACKUP_PATH/"

# Compress
tar -czf "$BACKUP_PATH.tar.gz" -C "$BACKUP_DIR" "state-$TIMESTAMP"
rm -rf "$BACKUP_PATH"

# Retain last 24 backups (24 hours if hourly)
ls -t "$BACKUP_DIR"/state-*.tar.gz | tail -n +25 | xargs -r rm

# Update orchestrator
jq --arg ts "$(date -Iseconds)" '.lastBackup = $ts' \
  .loki/state/orchestrator.json > tmp && mv tmp .loki/state/orchestrator.json

echo "Backup complete: $BACKUP_PATH.tar.gz"
```

### Log Rotation
```bash
#!/bin/bash
# .loki/scripts/rotate-logs.sh
# Run daily

LOG_DIR=".loki/logs"
ARCHIVE_DIR="$LOG_DIR/archive"
DATE=$(date +%Y%m%d)

mkdir -p "$ARCHIVE_DIR"

# Rotate main log
if [ -f "$LOG_DIR/LOKI-LOG.md" ]; then
  mv "$LOG_DIR/LOKI-LOG.md" "$ARCHIVE_DIR/LOKI-LOG-$DATE.md"
  echo "# Loki Mode Log - $(date +%Y-%m-%d)" > "$LOG_DIR/LOKI-LOG.md"
fi

# Rotate agent logs
for log in "$LOG_DIR/agents"/*.log; do
  [ -f "$log" ] || continue
  AGENT=$(basename "$log" .log)
  mv "$log" "$ARCHIVE_DIR/${AGENT}-${DATE}.log"
done

# Compress archives older than 7 days
find "$ARCHIVE_DIR" -name "*.md" -mtime +7 -exec gzip {} \;
find "$ARCHIVE_DIR" -name "*.log" -mtime +7 -exec gzip {} \;

# Delete archives older than 30 days
find "$ARCHIVE_DIR" -name "*.gz" -mtime +30 -delete

# Update orchestrator
jq --arg ts "$(date -Iseconds)" '.lastLogRotation = $ts' \
  .loki/state/orchestrator.json > tmp && mv tmp .loki/state/orchestrator.json
```

### External Alerting
```yaml
# .loki/config/alerting.yaml

channels:
  slack:
    webhook_url: "${SLACK_WEBHOOK_URL}"
    enabled: true
    severity: [critical, high]
  
  pagerduty:
    integration_key: "${PAGERDUTY_KEY}"
    enabled: false
    severity: [critical]
  
  email:
    smtp_host: "smtp.example.com"
    to: ["team@example.com"]
    enabled: true
    severity: [critical, high, medium]

alerts:
  system_down:
    severity: critical
    message: "Loki Mode system is down"
    channels: [slack, pagerduty, email]
  
  circuit_breaker_open:
    severity: high
    message: "Circuit breaker opened for {agent_type}"
    channels: [slack, email]
  
  dead_letter_queue:
    severity: high
    message: "{count} tasks in dead letter queue"
    channels: [slack, email]
  
  deployment_failed:
    severity: high
    message: "Deployment to {environment} failed"
    channels: [slack, pagerduty]
  
  budget_exceeded:
    severity: medium
    message: "Cloud costs exceeding budget by {percent}%"
    channels: [slack, email]
```

```bash
# Alert sending function
send_alert() {
  SEVERITY=$1
  MESSAGE=$2
  
  # Log locally
  echo "[$(date -Iseconds)] [$SEVERITY] $MESSAGE" >> .loki/logs/alerts.log
  
  # Send to Slack if configured
  if [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H 'Content-type: application/json' \
      -d "{\"text\":\"[$SEVERITY] Loki Mode: $MESSAGE\"}"
  fi
}
```

## Invocation

**"Loki Mode"** or **"Loki Mode with PRD at [path]"**

### Startup Sequence
```
╔══════════════════════════════════════════════════════════════════╗
║                    LOKI MODE v2.0 ACTIVATED                       ║
║              Multi-Agent Autonomous Startup System                ║
╠══════════════════════════════════════════════════════════════════╣
║ PRD:          [path]                                              ║
║ State:        [NEW | RESUMING]                                    ║
║ Agents:       [0 active, spawning initial pool...]                ║
║ Permissions:  [VERIFIED --dangerously-skip-permissions]           ║
╠══════════════════════════════════════════════════════════════════╣
║ Initializing distributed task queue...                            ║
║ Spawning orchestrator agents...                                   ║
║ Beginning autonomous startup cycle...                             ║
╚══════════════════════════════════════════════════════════════════╝
```

## Monitoring Dashboard

Generated at `.loki/artifacts/reports/dashboard.md`:
```
# Loki Mode Dashboard

## Agents: 12 active | 3 idle | 0 failed
## Tasks: 45 completed | 8 in-progress | 12 pending
## Release: v1.2.0 (deployed 2h ago)
## Health: ALL GREEN

### Recent Activity
- [10:32] eng-backend-02 completed: Implement user auth
- [10:28] ops-devops-01 completed: Configure CI pipeline
- [10:25] biz-marketing-01 completed: Landing page copy

### Metrics
- Uptime: 99.97%
- p99 Latency: 145ms
- Error Rate: 0.02%
- Daily Active Users: 1,247
```

## Red Flags - Never Do These

### Implementation Anti-Patterns
- **NEVER** skip code review between tasks
- **NEVER** proceed with unfixed Critical/High/Medium issues
- **NEVER** dispatch reviewers sequentially (always parallel - 3x faster)
- **NEVER** dispatch multiple implementation subagents in parallel (conflicts)
- **NEVER** implement without reading the task requirements first
- **NEVER** forget to add TODO/FIXME comments for Low/Cosmetic issues
- **NEVER** try to fix issues in orchestrator context (dispatch fix subagent)

### Review Anti-Patterns
- **NEVER** use sonnet for reviews (always opus for deep analysis)
- **NEVER** aggregate before all 3 reviewers complete
- **NEVER** skip re-review after fixes
- **NEVER** mark task complete with Critical/High/Medium issues open

### System Anti-Patterns
- **NEVER** delete .loki/state/ directory while running
- **NEVER** manually edit queue files without file locking
- **NEVER** skip checkpoints before major operations
- **NEVER** ignore circuit breaker states
- **NEVER** deploy without final review passing

### Always Do These
- **ALWAYS** launch all 3 reviewers in single message (3 Task calls)
- **ALWAYS** specify model: "opus" for each reviewer
- **ALWAYS** wait for all reviewers before aggregating
- **ALWAYS** fix Critical/High/Medium immediately
- **ALWAYS** re-run ALL 3 reviewers after fixes (not just the one that found issue)
- **ALWAYS** checkpoint state before spawning subagents
- **ALWAYS** log decisions with evidence in LOKI-LOG.md

### If Subagent Fails
1. Do NOT try to fix manually (context pollution)
2. Dispatch fix subagent with specific error context
3. If fix subagent fails 3x, move to dead letter queue
4. Open circuit breaker for that agent type
5. Alert orchestrator for human review

## Exit Conditions

| Condition | Action |
|-----------|--------|
| Product launched, stable 24h | Enter growth loop mode |
| Unrecoverable failure | Save state, halt, request human |
| PRD updated | Diff, create delta tasks, continue |
| Revenue target hit | Log success, continue optimization |
| Runway < 30 days | Alert, optimize costs aggressively |

## References

- `references/agents.md`: Complete agent type definitions and capabilities
- `references/deployment.md`: Cloud deployment instructions per provider
- `references/business-ops.md`: Business operation workflows
