# Optional manual patches

Daily CI syncs AWG helpers in `tools/sync_upstream_pr.sh`:

1. **Three-way merge** (`git merge-file`): base = bivlked pin, ours = Freedom, theirs = bivlked latest.
2. **Overlay fallback**: copy bivlked latest, re-apply Freedom customizations from `diff(bivlked pin, Freedom)`.

Add a `*.patch` here only when both strategies fail and you need a maintained manual overlay.
