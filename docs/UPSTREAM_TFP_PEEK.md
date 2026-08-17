# Upstream work item: `peekContinuousAi` in the DMD repo

**Status:** NOT DONE. This is a spec for work to be carried out **inside**
`~/code/DMD-control-flow-software`, not from this repo.

This repo treats the DMD repo as a read-only library (CLAUDE.md hard rule: *"NEVER write
into that repo from here"*). The change below was approved by the experimenter as
coordinated upstream work; it must be made in that repo, in its own commit, with its own
tests, following its conventions.

## Why

Mapping blocks run as one continuous DAQ session. During the block, the acquired AI lives in
`NI6323_DAQ`'s **private** `contAiBuf_` and there is no accessor, so the GUI cannot plot a
trial's response until `stopContinuousSession()` returns at block end. For a ~7 minute block
that means the operator flies blind the whole way.

There is a second, independent problem in the same code: the `DataAvailable` listener grows
its buffer by concatenation —

```matlab
contAiBuf_ = [contAiBuf_; evt.Data];   % O(n^2) over the block
```

— which `docs/DEPENDENCIES.md` already flags. Both are fixed in the same place.

## What to add

### `src/+tfp/+hardware/DAQ.m` (abstract)

Add one abstract method:

```matlab
data = peekContinuousAi(obj, range)
% Already-acquired AI from the running continuous session, WITHOUT disturbing it.
%   range = n       -> the last n samples
%   range = [i0 i1] -> that 1-based, inclusive sample range, clamped to what
%                      has actually been acquired
% Returns nSamples x nAiChannels in DAQ VOLTS. Returns a 0 x nAi array when
% nothing has been acquired yet.
% Errors tfp:hardware:DAQ:notRunning outside an active continuous session,
% and tfp:hardware:DAQ:badShape for a malformed range.
```

### `src/+tfp/+hardware/NI6323_DAQ.m`

1. Replace the concatenating buffer with a **preallocated, geometrically grown** buffer:
   keep `contAiBuf_` plus a fill count, preallocate to a few seconds of samples, and double
   on overflow. `stopContinuousSession` returns `contAiBuf_(1:fill, :)`.
2. Implement `peekContinuousAi` as a copy out of that buffer, honoring the fill count.
   Do not touch the session; this must be safe to call at GUI refresh rates.

### `src/+tfp/+hardware/MockDAQ.m`

Mirror the entry point so DMD-repo mock code has the same surface.

### Tests (that repo's style)

- Peek before any data → `0 x nAi`.
- Peek outside a session → `tfp:hardware:DAQ:notRunning`.
- Peek with a bad range → `tfp:hardware:DAQ:badShape`.
- Range clamping at both ends.
- Peeked samples equal the corresponding rows of the final `stopContinuousSession` record
  (true on real hardware and on `MockDAQ`; see the mock caveat below).
- Buffer growth: a long session does not exhibit quadratic time.

## Then, back in this repo

- `tests/test_tfp_api_surface.m` — add `peekContinuousAi` to the entry-point tripwire.
- `docs/DEPENDENCIES.md` — add it to the contracted surface and drop the O(n²) caveat.

## Already done on this side

`sem.hardware.MockEphysDAQ.peekContinuousAi` is implemented against this exact signature, and
`sem.protocol.EpisodicRunner.peekTrialWindow` already calls it behind an `ismethod` guard
(the same idiom as `sem.hardware.notifyStim`). So mapping blocks show live per-trial traces
on the mock **today**, and will do the same on the rig the moment the upstream change lands —
no further change in this repo beyond the two tripwire updates above.

**Mock caveat, deliberate:** `MockEphysDAQ` re-synthesizes on demand, so a peek and the final
record share the signal but not the noise realization. Peeked data is display-only there. On
real hardware the peek returns the actual acquired samples and the equality test above holds.
