"""Filesystem failures and real historical upgrades, entirely in temporary homes."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='mac-setup-transactions-')
        self.root = Path(self.tmp.name).resolve()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), MAC_SETUP_LIB='1',
                        PATH=f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin')
        for key in ('MAC_SETUP_MODE', 'MAC_SETUP_COMPONENTS', 'MAC_SETUP_PULLED', 'BASH_ENV'):
            self.env.pop(key, None)
        (self.bin / 'python3').symlink_to(sys.executable)
        self.checkout = self.root / 'checkout'
        shutil.copytree(REPO, self.checkout, ignore=shutil.ignore_patterns('.git', '__pycache__'))

    def tearDown(self):
        self.tmp.cleanup()

    def run_shell(self, script, **kwargs):
        return subprocess.run(['/bin/bash', '-c', script], cwd=self.checkout,
                              env=self.env, text=True, capture_output=True, timeout=30, **kwargs)

    def installer(self, script):
        return self.run_shell('source ./install.sh\n' + script)

    def stub(self, name, content):
        file = self.bin / name
        file.write_text('#!/bin/bash\n' + content + '\n')
        file.chmod(0o755)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def pointer(self, kind='link'):
        pointer = self.home / '.config/mac-setup/repo'
        pointer.parent.mkdir(parents=True)
        if kind == 'link':
            pointer.symlink_to('../../old-checkout')  # relative, dangling; exact target must survive rollback
        elif kind == 'real':
            pointer.mkdir()
            (pointer / 'precious').write_text('keep')
        return pointer

    def assert_pointer_preserved(self, pointer, kind):
        if kind == 'link':
            self.assertEqual(os.readlink(pointer), '../../old-checkout')
        elif kind == 'real':
            self.assertFalse(pointer.is_symlink())
            self.assertEqual((pointer / 'precious').read_text(), 'keep')
        else:
            self.assertFalse(os.path.lexists(pointer))
        self.assertEqual(list(pointer.parent.glob('repo.txn.*')), [])

    def test_incomplete_checkout_keeps_previous_pointer(self):
        pointer = self.pointer()
        (self.checkout / 'config/nvim/init.lua').unlink()
        result = self.installer('ensure_repo_link')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('incomplete or invalid', result.stdout)
        self.assert_pointer_preserved(pointer, 'link')
        self.assertFalse((self.home / '.zprofile').exists())

    def test_invalid_script_keeps_previous_pointer(self):
        pointer = self.pointer()
        (self.checkout / 'scripts/herdr-session.sh').write_text('if then\n')
        result = self.installer('ensure_repo_link')
        self.assertNotEqual(result.returncode, 0)
        self.assert_pointer_preserved(pointer, 'link')

    def test_pointer_postcheck_failure_rolls_back_all_previous_states(self):
        for kind in ('link', 'real', 'absent'):
            with self.subTest(kind=kind):
                pointer = self.pointer(kind)
                result = self.installer('''validate_checkout() { [ "$1" = "$REPO" ]; }
ensure_repo_link''')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assert_pointer_preserved(pointer, kind)
                shutil.rmtree(pointer.parent)

    def test_pointer_failed_rename_keeps_previous_target(self):
        pointer = self.pointer()
        result = self.installer('''atomic_rename() {
  case "$1" in */next) return 9 ;; esac
  /usr/bin/perl -e 'rename $ARGV[0], $ARGV[1] or die $!' -- "$1" "$2"
}
ensure_repo_link''')
        self.assertNotEqual(result.returncode, 0)
        self.assert_pointer_preserved(pointer, 'link')

    def test_pointer_success_backs_up_existing_real_directory(self):
        pointer = self.pointer('real')
        self.assert_success(self.installer('ensure_repo_link'))
        self.assertEqual(pointer.resolve(), self.checkout)
        backups = list(pointer.parent.glob('repo.bak-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'precious').read_text(), 'keep')

    def block(self, prefix=''):
        return self.installer(prefix + '''ensure_local_block '# >>> test >>>' <<'BLOCK'
# >>> test >>>
export NEW=yes
# <<< test <<<
BLOCK
''')

    def test_managed_update_preserves_relative_symlink_chain_and_mode(self):
        real = self.home / 'real'
        real.write_text('export MY_SETTING=yes\n')
        real.chmod(0o640)
        (self.home / 'middle').symlink_to('real')
        local = self.home / '.zshrc.local'
        local.symlink_to('middle')
        self.assert_success(self.block())
        self.assertEqual(os.readlink(local), 'middle')
        self.assertEqual(os.readlink(self.home / 'middle'), 'real')
        self.assertIn('export NEW=yes', real.read_text())
        self.assertEqual(real.stat().st_mode & 0o777, 0o640)
        self.assertEqual(next(self.home.glob('.zshrc.local.bak-*')).read_text(), 'export MY_SETTING=yes\n')

    def test_managed_cleanup_survives_component_local_variables(self):
        result = self.installer('''component() {
  local tmp file replacement target stage block
  ensure_local_block '# >>> test >>>' <<'BLOCK'
# >>> test >>>
export NEW=yes
# <<< test <<<
BLOCK
}
component''')
        self.assert_success(result)
        self.assertIn('export NEW=yes', (self.home / '.zshrc.local').read_text())
        self.assertEqual(list(self.home.glob('*.tmp.*')), [])

    def test_failed_managed_promotion_preserves_original(self):
        local = self.home / '.zshrc.local'
        local.write_text('export MY_SETTING=yes\n')
        result = self.block('atomic_rename() { return 9; }\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(local.read_text(), 'export MY_SETTING=yes\n')
        self.assertEqual(list(self.home.glob('*.tmp.*')), [])

    def test_invalid_shell_result_is_not_published(self):
        local = self.home / '.zshrc.local'
        local.write_text('export MY_SETTING=yes\n')
        result = self.installer('''ensure_local_block '# >>> test >>>' <<'BLOCK'
# >>> test >>>
if then
# <<< test <<<
BLOCK
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(local.read_text(), 'export MY_SETTING=yes\n')
        self.assertEqual(list(self.home.glob('.zshrc.local.bak-*')), [])

    def test_dangling_managed_symlink_is_not_created_or_replaced(self):
        local = self.home / '.zshrc.local'
        local.symlink_to('missing')
        result = self.block()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(os.readlink(local), 'missing')
        self.assertFalse((self.home / 'missing').exists())

    def interrupt(self, script):
        process = subprocess.Popen(['/bin/bash', '-c', 'source ./install.sh\n' + script],
                                   cwd=self.checkout, env=self.env, start_new_session=True,
                                   text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        ready = self.home / 'ready'
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and time.monotonic() < deadline and process.poll() is None:
                time.sleep(0.02)
            self.assertTrue(ready.exists(), 'did not reach staged write')
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=10)
            self.assertNotEqual(process.returncode, 0)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()

    def test_interrupted_managed_write_preserves_original(self):
        local = self.home / '.zshrc.local'
        local.write_text('export KEEP=yes\n')
        self.interrupt('''atomic_rename() { touch "$HOME/ready"; sleep 20; }
ensure_local_block '# >>> test >>>' <<'BLOCK'
# >>> test >>>
export NEW=yes
# <<< test <<<
BLOCK
''')
        self.assertEqual(local.read_text(), 'export KEEP=yes\n')
        self.assertEqual(list(self.home.glob('*.tmp.*')), [])

    def test_interrupted_pointer_verification_restores_previous(self):
        pointer = self.pointer()
        self.interrupt('''validate_checkout() {
  [ "$1" = "$REPO" ] && return 0
  touch "$HOME/ready"
  sleep 20
}
ensure_repo_link''')
        self.assert_pointer_preserved(pointer, 'link')

    def theme_fixture(self, mode='success'):
        self.env['THEME_MODE'] = mode
        self.env['THEME_SOURCE'] = str(REPO)
        self.stub('curl', '''case "$2" in
  */ghostty.config) cp "$THEME_SOURCE/config/ghostty/themes/lanna-tone" "$4" ;;
  */alacritty.toml)
    case "$THEME_MODE" in
      transfer) printf partial > "$4"; exit 22 ;;
      invalid) printf '<html>server error</html>' > "$4"; exit 0 ;;
      mismatch) sed 's/160b09/000000/g' "$THEME_SOURCE/config/alacritty/themes/lanna-tone.toml" > "$4"; exit 0 ;;
    esac
    cp "$THEME_SOURCE/config/alacritty/themes/lanna-tone.toml" "$4" ;;
  *) exit 99 ;;
esac''')
        ghostty = self.checkout / 'config/ghostty/themes/lanna-tone'
        alacritty = self.checkout / 'config/alacritty/themes/lanna-tone.toml'
        ghostty.write_text('previous Ghostty theme\n')
        alacritty.write_text('previous Alacritty theme\n')
        return ghostty, alacritty

    def test_theme_download_failures_leave_both_copies_unchanged(self):
        for mode in ('transfer', 'invalid', 'mismatch'):
            with self.subTest(mode=mode):
                ghostty, alacritty = self.theme_fixture(mode)
                result = self.run_shell('source scripts/sync-theme.sh\nsync_themes')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(ghostty.read_text(), 'previous Ghostty theme\n')
                self.assertEqual(alacritty.read_text(), 'previous Alacritty theme\n')

    def test_theme_second_promotion_failure_restores_both(self):
        ghostty, alacritty = self.theme_fixture()
        result = self.run_shell('''source scripts/sync-theme.sh
atomic_rename() {
  if [[ "$2" == *.toml ]] && [ ! -e "$HOME/failed-once" ]; then
    touch "$HOME/failed-once"; return 9
  fi
  /usr/bin/perl -e 'rename $ARGV[0], $ARGV[1] or die $!' -- "$1" "$2"
}
sync_themes''')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(ghostty.read_text(), 'previous Ghostty theme\n')
        self.assertEqual(alacritty.read_text(), 'previous Alacritty theme\n')
        self.assertEqual(list(self.checkout.rglob('*.tmp.*')), [])

    def test_interrupted_theme_promotion_restores_both(self):
        ghostty, alacritty = self.theme_fixture()
        self.interrupt('''source scripts/sync-theme.sh
atomic_rename() {
  if [[ "$2" == *.toml ]] && [ ! -e "$HOME/ready" ]; then
    touch "$HOME/ready"; sleep 20
  fi
  /usr/bin/perl -e 'rename $ARGV[0], $ARGV[1] or die $!' -- "$1" "$2"
}
sync_themes''')
        self.assertEqual(ghostty.read_text(), 'previous Ghostty theme\n')
        self.assertEqual(alacritty.read_text(), 'previous Alacritty theme\n')
        self.assertEqual(list(self.checkout.rglob('*.tmp.*')), [])

    def test_theme_success_keeps_mode_and_updates_both(self):
        ghostty, alacritty = self.theme_fixture()
        ghostty.chmod(0o640)
        self.assert_success(self.run_shell('source scripts/sync-theme.sh\nsync_themes'))
        self.assertEqual(ghostty.read_bytes(), (REPO / ghostty.relative_to(self.checkout)).read_bytes())
        self.assertEqual(alacritty.read_bytes(), (REPO / alacritty.relative_to(self.checkout)).read_bytes())
        self.assertEqual(ghostty.stat().st_mode & 0o777, 0o640)


class HistoricalUpgrades(unittest.TestCase):
    def test_documented_updates_from_previous_releases_apply_component(self):
        # Real historical source, local Git transport. CI fetches these commits.
        # Both pre-reliability and pre-pointer-fix versions must pull/re-exec all
        # the way through a component and doctor, with no early-exit test hooks.
        for revision in ('7f6e568cf930919f88cf45ac50b9c1273443fb23',
                         '1f96b03adf2846d5d49ae7e9c30a998c69a481e8'):
            for invocation in ('cwd', 'absolute'):
                with self.subTest(revision=revision, invocation=invocation), tempfile.TemporaryDirectory() as temp:
                    root = Path(temp).resolve()
                    home = root / 'home'
                    home.mkdir()
                    bin_dir = root / 'bin'
                    bin_dir.mkdir()
                    env = dict(os.environ, HOME=str(home),
                               PATH=f'{bin_dir}:/usr/bin:/bin:/usr/sbin:/sbin',
                               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null')
                    for key in ('MAC_SETUP_LIB', 'MAC_SETUP_MODE', 'MAC_SETUP_COMPONENTS',
                                'MAC_SETUP_PULLED', 'BASH_ENV'):
                        env.pop(key, None)
                    def run(*args, cwd=root, input=None):
                        return subprocess.run(args, cwd=cwd, env=env, input=input,
                                              capture_output=True, check=True, timeout=30)
                    publisher = root / 'publisher'
                    publisher.mkdir()
                    archive = run('git', '-C', str(REPO), 'archive', revision).stdout
                    run('tar', '-xf', '-', cwd=publisher, input=archive)
                    run('git', 'init', '-q', '-b', 'main', cwd=publisher)
                    def commit(message):
                        run('git', 'add', '-A', cwd=publisher)
                        run('git', '-c', 'user.name=test', '-c', 'user.email=test@example.com',
                            'commit', '-qm', message, cwd=publisher)
                    commit('historical source')
                    remote = root / 'origin.git'
                    run('git', 'clone', '-q', '--bare', str(publisher), str(remote))
                    checkout = root / 'checkout'
                    run('git', 'clone', '-q', str(remote), str(checkout))
                    # Advance origin to the working tree under test.
                    shutil.copytree(REPO, publisher, dirs_exist_ok=True,
                                    ignore=shutil.ignore_patterns('.git', '__pycache__'))
                    commit('current installer')
                    run('git', 'push', '-q', str(remote), 'main', cwd=publisher)
                    expected = run('git', 'rev-parse', 'HEAD', cwd=publisher).stdout
                    pointer = home / '.config/mac-setup/repo'
                    pointer.parent.mkdir(parents=True)
                    pointer.symlink_to(checkout)
                    (pointer.parent / 'selection').write_text('components=macos\n')
                    (home / '.zshrc').symlink_to(pointer / 'home/zshrc')
                    (home / '.zprofile').write_text('export MY_LOCAL_SETTING=yes\n')
                    (home / 'brew').mkdir()
                    for name, script in {
                        'brew': '''case "$1" in
shellenv|list) exit 0 ;;
--prefix) printf '%s\\n' "$HOME/brew" ;;
*) echo "unexpected brew: $*" >&2; exit 99 ;;
esac''',
                        'defaults': '''case "$1" in
write) printf '%s\\n' "$*" >> "$HOME/defaults-writes" ;;
read) echo 1 ;;
*) exit 99 ;;
esac''',
                        'curl': 'echo unexpected-network >&2; exit 99',
                    }.items():
                        stub = bin_dir / name
                        stub.write_text('#!/bin/bash\n' + script + '\n')
                        stub.chmod(0o755)
                    command = ('cd "$HOME/.config/mac-setup/repo" && ./install.sh update'
                               if invocation == 'cwd' else '"$HOME/.config/mac-setup/repo/install.sh" update')
                    result = run('/bin/bash', '-c', command)
                    output = result.stdout.decode()
                    self.assertIn('[macos] system tweaks', output)
                    self.assertIn('update complete: pulled and applied selected components', output)
                    self.assertEqual(run('git', 'rev-parse', 'HEAD', cwd=checkout).stdout, expected)
                    self.assertEqual(pointer.resolve(), checkout)
                    self.assertEqual((home / '.zshrc').resolve(), checkout / 'home/zshrc')
                    self.assertEqual((pointer.parent / 'selection').read_text(), 'components=macos\n')
                    self.assertIn('export MY_LOCAL_SETTING=yes', (home / '.zprofile').read_text())
                    self.assertEqual((home / 'defaults-writes').read_text(),
                                     'write -g NSWindowShouldDragOnGesture -bool true\n')


if __name__ == '__main__':
    unittest.main()
