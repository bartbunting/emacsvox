# Updating the Piper catalogue

`omnivox-piper-catalogue.py` is a Python 3.9+ maintainer tool using only the
standard library. It prepares catalogue metadata; Omnivox continues to own
user downloads, storage, native validation, installation and activation.
Nothing here enables voices or changes a running speech session.

Use a work directory on a disk with room for the models. The full upstream
collection can exceed 10 GiB. The ignored `.voice-catalogue-work/` directory
is suitable; `/tmp` may be a small memory filesystem.

## Discover and review

```sh
python3 utils/omnivox-piper-catalogue.py discover --work .voice-catalogue-work
python3 utils/omnivox-piper-catalogue.py metadata --work .voice-catalogue-work
```

Discovery resolves `main` once, records the immutable repository revision,
and checks the index against that revision's file metadata. Repeating discovery
at the same revision preserves work; use another directory for a new revision.
Metadata downloads the pinned configuration and model card for each model and
computes their SHA-256 checksums. LFS model hashes are initially expected values,
not evidence that the model has been downloaded and checked.

Read each model card under `assets/ID/MODEL_CARD`. Check attribution, stated
dataset and model terms, and runtime requirements. Follow referenced terms
where the card does not state them; leave unclear entries pending. A dataset
licence is not an unconditional statement about all model uses. Review notes
should attribute claims to the card and preserve restrictions and provenance.

```sh
python3 utils/omnivox-piper-catalogue.py review --work .voice-catalogue-work \
  --id piper-en-us-kristin-medium --reviewer 'Reviewer name' \
  --note 'Model card declares the LibriVox dataset public domain; see retained model card for provenance and training details.'
```

Review is explicit per ID; repeat `--id` only for models covered by that review.
The review binds the exact entry, including sources, files, speakers and terms.
Models exceeding Omnivox's 256-speaker projection limit remain in review data
with a blocking reason. No speakers are silently removed.

## Validate and export

```sh
python3 utils/omnivox-piper-catalogue.py validate --work .voice-catalogue-work \
  --server /absolute/path/to/omnivox \
  --helper /absolute/path/to/omnivox-piper-helper
python3 utils/omnivox-piper-catalogue.py status --work .voice-catalogue-work
python3 utils/omnivox-piper-catalogue.py export --work .voice-catalogue-work \
  --output etc/omnivox-piper-catalogues
```

Validation downloads and hashes the model, then invokes the native development
validator with explicit paths, isolated generations and no playback. Omnivox
checks the complete speaker projection, synthesizes each speaker and confirms
child cleanup. The default budget is 2 GiB and 60 seconds per model; `--jobs`
defaults to four concurrent models. Lower concurrency on smaller machines.
Use `--timeout` or `--memory-mib` explicitly when a model needs a larger budget.
These are validation budgets, not estimates of installed voice memory usage.

Without IDs, validation selects reviewed, unblocked models that lack current
passing evidence. Explicit IDs allow retries. Failed items retain logs and
return a nonzero command status; successful work remains reusable. Native
scratch may also remain after failure. Review it before removing it. Evidence
records the platform, validator identity and cleanup result; passing on one
platform does not establish acceptance on another or guarantee speech quality.
End-user installation still performs validation on the user's native host.

Export includes only entries with current review, verified file hashes and
matching native evidence. It writes language shards within Omnivox's limits of
128 entries and 1 MiB per document. Content-derived filenames and an atomic
manifest preserve the preceding catalogue if export is interrupted. Old shards
are not deleted automatically. `review-report.json` retains the disposition of
the entire discovered collection, including pending and failed entries.
The browser reads only files named in `manifest.json`, validates each through
Omnivox, and retains the exact document for installation. Its original catalogue
takes precedence for existing IDs such as Kristin.

Review generated changes and run the importer regressions before committing:

```sh
python3 -m unittest discover -s test -p test_piper_catalogue.py
```

Model weights and the local asset cache are never committed. Catalogue refresh,
download resume, automatic package updates, and signed review attestations are
future work; this tool does not imply those guarantees.
