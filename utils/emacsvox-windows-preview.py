#!/usr/bin/env python3
"""Prepare, check, tag or publish a Windows preview from a successful CI run."""
# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later

import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('sources', ROOT / 'utils/emacsvox-windows-sources.py')
SOURCES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SOURCES)
sha256 = SOURCES.BUNDLE.sha256
read_json = SOURCES.read_json
write_json = SOURCES.write_json
ARTIFACTS = {'installer': 'emacsvox-windows-installer',
             'sources': 'emacsvox-windows-sources',
             'evidence': 'emacsvox-windows-installer-evidence'}


def run(*args, root=ROOT):
    return subprocess.check_output(args, cwd=root).decode().strip()


def api(repository, path, pages=False):
    args = ['gh', 'api', f'repos/{repository}/{path}']
    if pages:
        args += ['--paginate', '--slurp']
    result = json.loads(run(*args))
    return [item for page in result for item in page] if pages else result


def require(condition, message):
    if not condition:
        raise ValueError(message)


def tag_name(tag):
    require(re.fullmatch(r'windows-preview-\d{4}-\d{2}-\d{2}', tag),
            'Use a separate windows-preview-YYYY-MM-DD tag')
    datetime.date.fromisoformat(tag.removeprefix('windows-preview-'))
    return tag


def push_url(root, remote):
    urls = run('git', 'remote', 'get-url', '--push', '--all', remote, root=root).splitlines()
    require(len(urls) == 1 and re.fullmatch(
        r'(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)[\w.-]+/[\w.-]+/?', urls[0]),
        'Use one explicit GitHub push destination')
    return urls[0]


def checkout(root, remote):
    require(not run('git', 'status', '--porcelain', '--untracked-files=all', root=root),
            'Preview preparation and publication require a clean committed checkout; work was preserved')
    url = push_url(root, remote)
    repository = run('gh', 'repo', 'view', url, '--json', 'nameWithOwner', '--jq', '.nameWithOwner')
    require(re.fullmatch(r'[\w.-]+/[\w.-]+', repository), 'Cannot resolve the release repository')
    return repository, run('git', 'rev-parse', 'HEAD', root=root)


def checked_ci(repository, run_id, commit=None):
    ci = api(repository, f'actions/runs/{int(run_id)}')
    require(ci['status'] == 'completed' and ci['conclusion'] == 'success',
            'The complete CI run must have passed')
    require(ci['repository']['full_name'] == repository and
            ci['head_repository']['full_name'] == repository and
            ci['path'] == '.github/workflows/ci.yml' and
            ci['head_branch'] == 'master' and ci['event'] in {'push', 'workflow_dispatch'},
            'Use a trusted master CI run from the publication repository')
    require(commit is None or ci['head_sha'] == commit, 'CI source commit changed')
    return ci


def checked_sources(root, assets, pair, setup):
    """Match every archived source to Git without extracting or executing it."""
    commit = pair['SourceCommit']
    require(re.fullmatch(r'[0-9a-f]{40,64}', commit), 'Invalid source commit')
    run('git', 'merge-base', '--is-ancestor', commit, 'HEAD', root=root)
    tree = {}
    for entry in run('git', 'ls-tree', '-rz', commit, root=root).rstrip('\0').split('\0'):
        metadata, name = entry.split('\t', 1)
        mode, kind, oid = metadata.split()
        if not name.startswith(SOURCES.UNSHIPPED_RECORDINGS):
            require(kind == 'blob' and mode in {'100644', '100755', '120000'},
                    f'Unsupported source entry: {name}')
            tree['emacsvox/' + name] = (int(mode, 8), oid)
    object_format = run('git', 'rev-parse', '--show-object-format', root=root)
    with zipfile.ZipFile(assets / pair['SourceArchive']) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)) and set(names) == set(tree) | {
            'source-manifest.json', 'README.txt', 'SOURCE-DOWNLOADS.md'},
            'Source ZIP contains missing, duplicate or unexpected files')
        inventory = json.loads(archive.read('source-manifest.json'))
        for key in ['Build', 'SourceCommit', 'Installer', 'InstallerSHA256', 'RunURL']:
            require(inventory[key] == pair[key], f'Source pairing mismatch: {key}')
        require(inventory['Schema'] == 1 and
                inventory['SetupManifestSHA256'] == sha256(assets / 'setup-manifest.json'),
                'Source ZIP does not match the setup manifest')
        files = inventory['Files']
        require(len(files) == len(tree) and {item['Path'] for item in files} == set(tree),
                'Source inventory differs from the committed tree')
        hashes = {}
        for item in files:
            name = item['Path']
            contents = archive.read(name)
            digest = hashlib.sha256(contents).hexdigest()
            mode, oid = tree[name]
            blob = hashlib.new(object_format, f'blob {len(contents)}\0'.encode() + contents).hexdigest()
            require(blob == oid and digest == item['SHA256'] and int(item['Mode'], 8) == mode and
                    archive.getinfo(name).external_attr >> 16 == mode,
                    f'Archived source differs from Git: {name}')
            hashes[name.removeprefix('emacsvox/')] = digest
        lock = json.loads(archive.read('emacsvox/' + SOURCES.LOCK))
        require(inventory['SourceLockSHA256'] == hashes[SOURCES.LOCK] and
                inventory['UpstreamSources'] == lock['Archives'] and
                inventory['RuntimeSHA256'] == lock['RuntimeSHA256'], 'Source lock mismatch')
        index = archive.read('SOURCE-DOWNLOADS.md')
        require(index == (assets / 'SOURCE-DOWNLOADS.md').read_bytes() and
                index.decode().replace('\r\n', '\n') == SOURCES.source_index(lock),
                'Upstream source directions differ from the reviewed source lock')
        require(archive.read('README.txt') == archive.read('emacsvox/etc/windows-sources.txt'),
                'Source build instructions changed')
        for name, digest in setup['SetupInputs'].items():
            require(hashes.get(name) == digest, f'Setup input differs from source: {name}')
        prefix = f'Applications/{pair["Build"]}/'
        app = {item['Path'][len(prefix):]: item['SHA256'] for item in setup['Files']
               if item['Path'].startswith(prefix)}
        require(app == {name: digest for name, digest in hashes.items() if SOURCES.BUNDLE.include(name)},
                'Installer application inventory differs from the source archive')
        pins = dict(line.split('=', 1) for line in
                    archive.read('emacsvox/etc/wsl-install.conf').decode().splitlines()
                    if line.startswith('EMACSVOX_') and '=' in line)
        return {'Emacsvox': archive.read('emacsvox/VERSION').decode().strip(),
                'Emacs': pins['EMACSVOX_WSL_EMACS_VERSION'],
                'Omnivox': pins['EMACSVOX_WSL_OMNIVOX_VERSION']}


def checked_assets(root, assets, ci):
    pair = read_json(assets / 'downloads.json')
    require(pair['Schema'] == 1 and pair['SourceCommit'] == ci['head_sha'] and
            pair['RunURL'] == ci['html_url'], 'Downloads do not match the successful CI run')
    for key in ['Installer', 'SourceArchive']:
        name = pair[key]
        require(re.fullmatch(r'[A-Za-z0-9_.-]+', name), 'Unsafe asset filename')
        require(sha256(assets / name) == pair[key + 'SHA256'], f'{key} checksum mismatch')
        require((assets / (name + '.sha256')).read_text().split() == [pair[key + 'SHA256'], name],
                f'{key} checksum sidecar mismatch')
    require(pair['Installer'].endswith('-setup.exe') and pair['SourceArchive'].endswith('-sources.zip'),
            'Unexpected Windows download names')
    provenance = read_json(assets / (pair['Installer'] + '.provenance.json'))
    require(provenance['InstallerSHA256'] == pair['InstallerSHA256'] and
            provenance['ManifestSHA256'] == sha256(assets / 'setup-manifest.json'),
            'Installer compiler provenance mismatch')
    setup = read_json(assets / 'setup-manifest.json')
    require(setup['Schema'] == 1 and setup['BundleSourceCommit'] == pair['SourceCommit'] and
            setup['Build'] == pair['Build'], 'Setup source identity mismatch')
    lifecycle = read_json(assets / 'lifecycle-result.json')
    require(lifecycle['Schema'] == 1 and lifecycle['Passed'] is True and
            lifecycle['RollbackRequested'] is True, 'Native installer lifecycle checks did not pass')
    return pair, checked_sources(root, assets, pair, setup)


def notes(repository, tag, pair, versions):
    download = f'https://github.com/{repository}/releases/download/{tag}'
    return f'''# Emacsvox Windows preview — {tag.removeprefix("windows-preview-")}

Try the new per-user installer for native Windows x64. This is a preview of
development after Emacsvox {versions["Emacsvox"]}; it is not a new stable Emacsvox release.
It includes Emacs {versions["Emacs"]}, Omnivox {versions["Omnivox"]}, and Emacsvox.
No administrator privileges, Git, compiler or WSL are needed.

## Install and start

1. [Download the Windows installer]({download}/{pair["Installer"]}) and run it.
2. Follow the setup wizard. The finish page offers a speech test and Start Emacsvox.
3. Later, use Start > Emacsvox Windows, or the desktop shortcut if you selected it.

The installer is unsigned; Windows may display an unfamiliar-publisher warning.
Check that the file came from this release. The matching `.sha256` file records
its checksum. The default installation folder is `%LOCALAPPDATA%\\Emacsvox\\Desktop Dev`.
The wizard still shows version {versions["Emacsvox"]}; the download's development build
identifier distinguishes this preview: `{pair["Build"]}`.

Close this installation's Emacs and speech workers before repair or uninstall.
Remove it through Windows Settings > Apps > Emacsvox Windows. Personal data is
kept by default; optional cleanup choices are initially unchecked.

## Please test

- Install, hear the finish-page speech test, and launch from the Start menu.
- Navigate the welcome screen and change a voice. Try hiding and reopening Welcome.
- Check that your screen reader reads the wizard, options, completion and uninstall pages.
- Report unclear instructions, missing speech or installation errors in
  [the issue tracker](https://github.com/{repository}/issues), quoting the build above.

[The complete CI run passed]({pair["RunURL"]}), including native installation,
shortcut launch, busy-process refusal, repair, failed-upgrade rollback and
uninstall preservation. CI does not check audible speech or screen-reader use.
Broader clean-machine acceptance, a successful second-build upgrade and full
optional-cleanup lifecycle testing remain before stable installer release.

## Sources and build information

Sources are optional; you need only the installer to run Emacsvox.
[Our matching source ZIP]({download}/{pair["SourceArchive"]}) contains the exact
Emacsvox code, build scripts and runtime assets. [SOURCE-DOWNLOADS.md]({download}/SOURCE-DOWNLOADS.md)
links to matching Emacs, library and Omnivox sources on their upstream hosts,
with checksums. Those large third-party archives are not mirrored here.
Keep these sources and locations available when redistributing the installer.

Source commit: `{pair["SourceCommit"]}`. The original installer, source ZIP and
compiler provenance are unchanged from CI. Attached manifests and checksums
record the build and test evidence. These release downloads are public and
are not subject to CI artifact retention.
'''


def prepare(root, remote, run_id, tag, directory):
    tag_name(tag)
    require(not directory.exists(), 'Output directory already exists; work was preserved')
    repository, publisher = checkout(root, remote)
    ci = checked_ci(repository, run_id)
    directory.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.windows-preview-', dir=directory.parent) as temporary:
        work = Path(temporary)
        assets = work / 'assets'
        assets.mkdir()
        for kind, artifact in ARTIFACTS.items():
            run('gh', 'run', 'download', str(run_id), '--repo', repository, '--name', artifact,
                '--dir', str(work / kind))
        pair = read_json(work / 'installer/downloads.json')
        require(pair == read_json(work / 'sources/downloads.json'), 'CI download pairing differs')
        require((work / 'installer/SOURCE-DOWNLOADS.md').read_bytes() ==
                (work / 'sources/SOURCE-DOWNLOADS.md').read_bytes(), 'CI source indexes differ')
        for source in (work / 'installer').iterdir():
            if source.name != 'README.txt':
                shutil.copyfile(source, assets / source.name)
        for source in (work / 'sources').iterdir():
            if source.name not in {'downloads.json', 'SOURCE-DOWNLOADS.md'}:
                shutil.copyfile(source, assets / source.name)
        shutil.copyfile(work / 'evidence/setup/setup-manifest.json', assets / 'setup-manifest.json')
        shutil.copyfile(work / 'evidence/lifecycle/result.json', assets / 'lifecycle-result.json')
        pair, versions = checked_assets(root, assets, ci)
        (assets / 'README-preview.md').write_text(notes(repository, tag, pair, versions), encoding='utf-8')
        write_json(assets / 'preview-build.json', {
            'Schema': 1, 'Tag': tag, 'Repository': repository, 'SourceCommit': pair['SourceCommit'],
            'PublisherCommit': publisher, 'RunID': ci['id'], 'RunAttempt': ci['run_attempt'],
            'RunURL': ci['html_url'], 'Versions': versions,
            'Lifecycle': read_json(assets / 'lifecycle-result.json')})
        write_json(work / 'preview.json', {
            'Schema': 1, 'Tag': tag, 'Repository': repository, 'SourceCommit': pair['SourceCommit'],
            'PublisherCommit': publisher, 'RunID': ci['id'],
            'Files': {p.name: sha256(p) for p in sorted(assets.iterdir())}})
        for kind in ARTIFACTS:
            shutil.rmtree(work / kind)
        require(checkout(root, remote) == (repository, publisher), 'Publication checkout changed')
        work.rename(directory)
    return check(root, remote, directory)


def check(root, remote, directory):
    receipt = read_json(directory / 'preview.json')
    tag_name(receipt['Tag'])
    require(receipt['Schema'] == 1, 'Unsupported preview receipt')
    require(checkout(root, remote) == (receipt['Repository'], receipt['PublisherCommit']),
            'Publication repository or tooling commit changed; prepare again')
    assets = directory / 'assets'
    require({p.name for p in assets.iterdir()} == set(receipt['Files']), 'Preview asset set changed')
    for name, digest in receipt['Files'].items():
        require(re.fullmatch(r'[A-Za-z0-9_.-]+', name) and sha256(assets / name) == digest,
                f'Prepared preview changed: {name}')
    ci = checked_ci(receipt['Repository'], receipt['RunID'], receipt['SourceCommit'])
    pair, versions = checked_assets(root, assets, ci)
    require((assets / 'README-preview.md').read_text() == notes(receipt['Repository'], receipt['Tag'], pair, versions),
            'Preview instructions changed')
    expected = {'downloads.json', 'SOURCE-DOWNLOADS.md', 'setup-manifest.json', 'lifecycle-result.json',
                'README-preview.md', 'preview-build.json', pair['Installer'] + '.provenance.json'}
    for key in ['Installer', 'SourceArchive']:
        expected.update({pair[key], pair[key] + '.sha256'})
    require(set(receipt['Files']) == expected, 'Unexpected publication assets')
    return receipt


def remote_tag(root, remote, tag):
    result = run('git', 'ls-remote', '--refs', push_url(root, remote), f'refs/tags/{tag}', root=root)
    return result.split()[0] if result else None


def existing_release(repository, tag):
    releases = api(repository, 'releases?per_page=100', pages=True)
    return next((release for release in releases if release['tag_name'] == tag), None)


def create_tag(root, remote, receipt):
    tag, repository = receipt['Tag'], receipt['Repository']
    require(not run('git', 'tag', '--list', tag, root=root) and
            not remote_tag(root, remote, tag) and not existing_release(repository, tag),
            'Preview tag or release already exists; nothing was replaced')
    run('git', '-c', 'tag.gpgSign=false', 'tag', '-a', '--no-sign', tag,
        receipt['SourceCommit'], '-m', f'Emacsvox Windows preview {tag}', root=root)


def checked_draft(release, receipt, body):
    # GitHub ignores target_commitish when a tag already exists. The caller
    # verifies the annotated local and remote tag objects instead.
    require(release['draft'] and release['prerelease'] and release['tag_name'] == receipt['Tag'] and
            release['body'] == body,
            'Existing release is not the matching unpublished preview; nothing was replaced')
    present = set()
    for asset in release['assets']:
        name = asset['name']
        require(name not in present and name in receipt['Files'] and asset['state'] == 'uploaded' and
                asset.get('digest') == 'sha256:' + receipt['Files'][name],
                f'Unexpected or changed draft asset: {name}')
        present.add(name)
    return present


def publish(root, remote, directory, receipt):
    tag, repository = receipt['Tag'], receipt['Repository']
    ref = f'refs/tags/{tag}'
    require(run('git', 'cat-file', '-t', ref, root=root) == 'tag' and
            run('git', 'rev-parse', ref + '^{commit}', root=root) == receipt['SourceCommit'],
            'An annotated tag of the checked installer source is required')
    tag_object = run('git', 'rev-parse', ref, root=root)
    require(remote_tag(root, remote, tag) in {None, tag_object}, 'Remote tag differs; nothing was replaced')
    body = (directory / 'assets/README-preview.md').read_text()
    release = existing_release(repository, tag)
    if release:
        checked_draft(release, receipt, body)
    run('git', 'push', remote, ref, root=root)
    if not release:
        run('gh', 'release', 'create', tag, '--repo', repository, '--verify-tag', '--draft',
            '--prerelease', '--latest=false', '--target', receipt['SourceCommit'],
            '--title', f'Emacsvox Windows preview {tag.removeprefix("windows-preview-")}',
            '--notes-file', str(directory / 'assets/README-preview.md'))
        release = existing_release(repository, tag)
    present = checked_draft(release, receipt, body)
    # Upload sources before the executable. Keep everything private in the draft
    # until the complete remote asset set has the prepared SHA256 values.
    missing = sorted(set(receipt['Files']) - present)
    for binary in [False, True]:
        batch = [name for name in missing if name.endswith('.exe') == binary]
        if batch:
            run('gh', 'release', 'upload', tag, '--repo', repository,
                *(str(directory / 'assets' / name) for name in batch))
    require(checked_draft(existing_release(repository, tag), receipt, body) == set(receipt['Files']),
            'Draft is incomplete; it remains unpublished')
    check(root, remote, directory)
    require(remote_tag(root, remote, tag) == tag_object, 'Remote tag changed before publication')
    run('gh', 'release', 'edit', tag, '--repo', repository, '--verify-tag',
        '--draft=false', '--prerelease', '--latest=false')
    released = existing_release(repository, tag)
    require(not released['draft'] and released['prerelease'], 'Check GitHub publication state')
    return released['html_url']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'check', 'tag', 'publish'])
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--remote', default='origin')
    parser.add_argument('--run-id', type=int)
    parser.add_argument('--tag')
    args = parser.parse_args()
    directory = args.directory.resolve()
    if args.action == 'prepare':
        require(args.run_id and args.tag, 'Preparation requires --run-id and --tag')
        receipt = prepare(ROOT, args.remote, args.run_id, args.tag, directory)
    else:
        receipt = check(ROOT, args.remote, directory)
        if args.action == 'tag':
            create_tag(ROOT, args.remote, receipt)
        elif args.action == 'publish':
            print(publish(ROOT, args.remote, directory, receipt))
    print(f'{args.action}: {receipt["Tag"]}; installer source {receipt["SourceCommit"]}')


if __name__ == '__main__':
    main()
