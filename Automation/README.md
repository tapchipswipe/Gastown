# Trusted Newton backlog

`backlog.json` is read from committed HEAD only. Keep it a JSON array (at most 100 items). Each item requires `id`, `title`, `objective`, and a `completion` object containing `description`, `relativePath` and `requiredText`. The queue verifies tests, the production build and that explicit file-content criterion before recording verified status. Use real development tasks, never sample/fabricated work.

Mail, OCR, transcripts and arbitrary idea text have no queue-intake API. A job remains in its committed-HEAD worktree for review; Newton does not merge, push or release it. Interrupted jobs are retained for review and not automatically replayed. The separate saved opt-in and rollout acceptance gate must both be satisfied before admission.
