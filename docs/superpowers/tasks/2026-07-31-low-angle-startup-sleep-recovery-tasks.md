# Milestone 17 — 低角度啟動睡眠恢復 Task Register

日期：2026-07-31；remote sync：2026-08-01
狀態：Milestone 17 holistic closure 與 remote sync complete。Installed identity `7bf98ff6ceae` 已完成 upgrade、三階段 acceptance、persistent activation與低角度 reboot/loginwindow proof。Task 7R／7R2已修復兩次fail-stop所暴露的README contract drift與macOS diagnostics compatibility defect。Final main `2cd8b62f0f1bb86e2bf9286017b1ae396ff92803` 的current與exact-commit clean snapshot均為300 tests、1 skip、0 failures，release/static/package全部通過；live status／diagnostics／operational-baseline均rc 0。Production enabled／loaded／single PID `281`、monitoring-armed、crash clean、artifact count 0。使用者已於2026-08-01明確批准push，`origin/main` 已同步完整closure authority。

## Task register

| Task | Purpose | Primary evidence | Approval | Safe stop / rollback |
| ---: | --- | --- | --- | --- |
| 1 | Startup-closed RED contract — complete | state-machine/coordinator failing tests | repository work approved by Milestone design | abandon worktree; live production unchanged |
| 2 | Shared startup closed state machine — complete | focused GREEN tests and immediate review | none beyond repository implementation | revert Task 2 commit; live production unchanged |
| 3 | Shared composition equivalence — complete | foreground/production integration tests | none beyond repository implementation | revert Task 3 commit |
| 4 | README/runbook/event authority sync — complete | docs/event focused tests | none beyond repository implementation | revert Task 4 commit |
| 5 | Repository holistic release gate — complete | 289 tests in current/clean clone; release/static/package gates; live old identity unchanged | separate approval required for push or production mutation | candidate remains local; current production unchanged |
| 6 | Upgrade and bounded acceptance for new identity — complete | identity `7bf98ff6ceae`; dry-run、enabled-once、recovery-resleep all pass | approved fail-stop batch plus recovery-only retest | loaded/disabled/zero PID, crash count 0 |
| 6R | Repair maintenance bootout resident-process race — complete, integrated and deployed | 93 management tests, 292 full tests, timeout-before-replacement, release/static/package gates, real upgrade retry pass | completed under separate upgrade approval | installed identity `93d9881ecddb`, loaded/disabled/zero PID |
| 6R2 | Repair acceptance clean-exit/bootstrap handoff race — complete, integrated, superseded by 6R3 | 97 management tests, 296 full tests, delayed clean-state wait, timeout no-bootstrap, crash-count preservation, release/static/package gates, ff-only integration | historical recovery authority only | no independent open production scope remains |
| 6R3 | Repair overlapping termination and signal-handler completion race — complete | true double-SIGTERM child RED/GREEN, single bootout authority, 98 management tests, 299 full tests, final package `7bf98ff6ceae`, three-stage production acceptance | repository plus bounded production re-entry approved as one fail-stop batch; recovery-only retest separately approved | loaded/disabled/zero PID; crash count 0; no activate/reboot/push |
| 7 | Persistent activation and low-angle reboot/loginwindow proof — complete | prepared boot/PID `1785457249`/`99898`; new boot/PID `1785491605`/`281`; pre-login=true; startup sleep、wake/rearm、baseline、cleanup；final current/clean 300 tests and live read-only gate pass | activate、reboot preparation、manual reboot、finish、holistic closure與remote push均分開批准並完成 | production remains enabled/single PID; emergency disable/bootout only with approval |
| 7R | Synchronize README deployment-state contract — complete | focused RED 1 test/2 assertions; focused GREEN 1/1; full suite 299 tests, 1 skip, 0 failures; management 98/98 | explicitly approved recovery scope | historical recovery complete；final Step 5 subsequently closed |
| 7R2 | Repair macOS diagnostics process metrics — complete | real-process RED; `etimes`→`etime`; current/clean 300 tests, 1 skip, 0 failures; management 99/99; release/static/package; live diagnostics rc 0 | explicitly approved recovery scope | historical recovery complete；final Step 5 subsequently closed |

## Stage gates

### Stage A — Repository behavior — complete

Tasks 1–4 已在 isolated worktree 完成並通過 immediate reviews；沒有改變 `/Library` 或 launchd。

### Stage B — Repository holistic release — complete

Task 5 已通過 current checkout 與 valid clean clone 的 289-test、release、static、package gates；live production 僅做只讀核對。候選 commits 已 fast-forward 整合回本機 `main`。

### Stage C — Production deployment and final closure — complete

Final identity `7bf98ff6ceae` 已完成 upgrade、crash-state repair、dry-run、enabled-once與
recovery-resleep。首次 recovery-resleep 人工測試因顯示器亮起後只等待約 20 秒而中止；同一
sleep transaction 的 `pmset` evidence 顯示 `LINE timed out(30000 ms)`，而 15 秒 recovery 是從
`systemHasPoweredOn` 起算。保持低角度至少 60 秒的 recovery-only retest 隨後通過。

Task 7 Step 1 已在完整 matching acceptance 下執行 evidence-gated `activate`。PID `99898` 完成
startup cooldown 後進入 `monitoring-armed`，`operational_baseline=pass`；最終 production 為
enabled／loaded／single PID、crash count 0。Step 2 隨後以 boot epoch `1785457249` 與 prepared
PID `99898` 建立 root-owned one-shot reboot observer；目前 observer loaded／not running、runs=1、
last exit code 0。Step 3 隨後由使用者手動 reboot 並在低角度停留 loginwindow。新 boot epoch
為 `1785491605`，production PID 為 `281`；新 PID 在 startup cooldown 後進入
`startup-closed-candidate`，完成 debounce 並發出 exactly one sleep request。17:54:05 wake 後
同一 PID 回到 `monitoring-armed`。Observer evidence 在新 boot 更新，但其受保護的 pre-login
console user、identity 與 PID 欄位已由 Step 4 root verifier 正式驗證：boot-changed=true、
pre-login=true、new PID `281`、完整 acceptance 與 `operational_baseline=pass`。只有全部驗證通過
後才清理 temporary reboot state、observer evidence、observer executable、observer plist 與
observer launchd job；cleanup 後 artifact count 0，production 仍 enabled／loaded／single PID、
crash count 0。Milestone holistic closure 仍由 Step 5 獨立治理。

Step 5 第一次 current-checkout full suite 依 fail-stop 規則停止於一個過期 README contract test：
測試仍要求候選階段的「尚未部署」文字。Task 7R 已以 RED→GREEN 最小修正 test authority，
完整 suite恢復 299 tests、1 skip、0 failures；沒有修改 README正式事實、runtime source或
production。Step 5 必須從頭重新執行，不能沿用失敗 run 的部分結果。


Step 5 第二次 run 的 current checkout 與 independent clean snapshot repository gates 均通過，
但最後 live read-only gate 在 `diagnostics_rc=1` fail-stop。Task 7R2 證明根因為 macOS `ps`
不支援 `etimes`；最小修正為 `etime` 並新增真實子進程 contract。Current／clean snapshot 均為
300 tests、1 skip、0 failures，management 99/99，release/static/package全部通過；live diagnostics
對 PID `281` 輸出有效 elapsed/cpu/rss/vsz 且 rc 0。Production全程保持 enabled／single PID，
installed payload未修改。該 recovery verification未被直接沿用；Step 5 隨後從final main
`2cd8b62f0f1bb86e2bf9286017b1ae396ff92803` 再次完整重跑。

Final Step 5 run 的current checkout與exact-commit independent clean snapshot均fresh通過300 tests、
1 child-only skip、0 failures，management 99/99；兩邊release、static、package prepare/verify與
manifest binding均通過。Final root read-only gate確認status rc 0、diagnostics rc 0、
`operational_baseline=pass pid=281`；前後production enabled／loaded／single PID、crash clean、
artifact count 0，Git clean。README completion state與test authority同步後，current與clean snapshot
再各自完整跑300 tests通過。Milestone 17本機closure完成。2026-08-01 remote push另行獲准；
closure commit `27ad074433d826ace4c59bc338dcd4d3e7eaba1d` 已同步到 `origin/main`，remote-sync authority
follow-up亦在同一批准範圍內推送，使local／remote current authority一致。

## Completion rule

Tasks 1–7、Stage A/B/C reviews、低角度 loginwindow reboot evidence、final baseline與holistic
review均已通過，因此Milestone 17本機closure complete。Remote push雖不是closure成立條件，但已於
2026-08-01另行明確批准並完成；local main與`origin/main`最終同步。

## Governance findings

Open P0 = 0。
Open P1 without disposition = 0。
