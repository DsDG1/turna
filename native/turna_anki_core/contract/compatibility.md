# Compatibility

- Different major: reject with `CONTRACT_VERSION_MISMATCH`.
- Same major, Dart minor < native minor: ignore unknown response fields.
- Same major, Dart minor > native minor: call new operations only when
  `ENGINE_INFO` capabilities include them.
- Field deletion, type change, or default-semantic change requires a major bump.
- Backend commit is injected at native build time from `contract/BACKEND_COMMIT`.
