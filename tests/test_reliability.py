"""No installs/network/real-home writes: exercise failures and user-data preservation."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class Reliability(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='mac-setup-reliability-')
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), MAC_SETUP_LIB='1',
                        PATH=f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin',
                        MAC_SETUP_MODE='', MAC_SETUP_COMPONENTS='', HERDR_PANE_ID='')
        for key in ('COMPONENTS', 'MAC_SETUP_PULLED', 'ZSH_CUSTOM'):
            self.env.pop(key, None)

    def tearDown(self):
        self.tmp.cleanup()

    def shell(self, script, input=None):
        return subprocess.run(['/bin/bash', '-c', 'source ./install.sh\n' + script],
                              cwd=REPO, env=self.env, input=input, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def stub(self, name, code):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + code + '\n')
        path.chmod(0o755)

    def test_managed_blocks_upgrade_preserve_user_text_and_backup(self):
        path = self.home / '.zshrc.local'
        original = 'export MY_SETTING="keep"\n# >>> test >>>\nold\n# <<< test <<<\n# after\n'
        path.write_text(original)
        path.chmod(0o640)
        command = '''ensure_local_block '# >>> test >>>' <<'BLOCK'
# >>> test >>>
new
# <<< test <<<
BLOCK
'''
        result = self.shell(command + command)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(path.read_text(), original.replace('\nold\n', '\nnew\n'))
        backups = list(self.home.glob('.zshrc.local.bak-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        self.assertEqual(path.stat().st_mode & 0o777, 0o640)

    def test_malformed_block_preserved(self):
        path = self.home / '.zshrc.local'
        original = '# >>> test >>>\nuser content without closing marker\n'
        path.write_text(original)
        result = self.shell("printf '# >>> test >>>\\nnew\\n# <<< test <<<\\n' | ensure_local_block '# >>> test >>>'")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), original)

    def test_legacy_nvm_migration(self):
        path = self.home / '.zshrc.local'
        original = r'''# before
export NVM_DIR="$HOME/.nvm"
[ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
# after
'''
        path.write_text(original)
        result = self.shell('migrate_legacy_nvm\nmigrate_legacy_nvm')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(path.read_text().count('# >>> mac-setup nvm >>>'), 1)
        self.assertIn('# before\n', path.read_text())
        self.assertTrue(path.read_text().endswith('# after\n'))

    def test_custom_nvm_is_not_overwritten(self):
        path = self.home / '.zshrc.local'
        original = 'export NVM_DIR="/custom/nvm"\n# mine\n'
        path.write_text(original)
        result = self.shell('migrate_legacy_nvm')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), original)

    def test_component_failure_does_not_skip_later_components(self):
        result = self.shell('''COMPONENTS="nvim shell"
comp_nvim() { echo NVIM-START; false; echo SHOULD-NOT-RUN; }
comp_shell() { echo SHELL-RAN; }
apply_components
''')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('SHELL-RAN', result.stdout)
        self.assertNotIn('SHOULD-NOT-RUN', result.stdout)
        self.assertIn('re-run: ./install.sh nvim', result.stdout)

    def test_nvim_exit_failure_propagates(self):
        self.stub('nvim', 'exit 9')
        result = self.shell('provision_nvim')
        self.assertEqual(result.returncode, 9, result.stdout)

    def test_bundle_failure_propagates(self):
        jq = shutil.which('jq')
        self.assertIsNotNone(jq)
        (self.bin / 'jq').symlink_to(jq)
        self.stub('brew', '''case "$1" in
list) exit 0;;
tap) exit 0;;
info) echo '{"casks":[]}' ;;
bundle) exit 7;;
*) exit 0;;
esac''')
        result = self.shell('comp_apps')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('brew bundle finished with errors', result.stdout)

    def test_doctor_reports_selected_missing_tools_and_identity(self):
        self.stub('brew', 'echo "herdr 1.2.3"')
        result = self.shell('COMPONENTS=agents\ndoctor_environment')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('branch=', result.stdout)
        self.assertIn('commit=', result.stdout)
        self.assertIn('herdr 1.2.3', result.stdout)
        self.assertIn('MISSING', result.stdout)
        self.assertIn('./install.sh agents', result.stdout)
        self.assertFalse((self.home / '.config').exists())

    def test_doctor_version_probe_times_out(self):
        self.stub('slowtool', 'exec sleep 30')
        self.env['MAC_SETUP_PROBE_TIMEOUT'] = '1'
        result = self.shell('diagnostic_component=nvim\ndoctor_command slowtool')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('timed out', result.stdout)

    def test_duplicate_block_preserved(self):
        path = self.home / '.zshrc.local'
        original = '# >>> test >>>\nold\n# <<< test <<<\n' * 2
        path.write_text(original)
        result = self.shell("printf '# >>> test >>>\\nnew\\n# <<< test <<<\\n' | ensure_local_block '# >>> test >>>'")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), original)

    def test_doctor_scopes_checks_to_selection(self):
        self.stub('brew', 'echo "herdr 1.2.3"')
        self.stub('defaults', 'echo 1')
        result = self.shell('COMPONENTS=macos\ndoctor_environment')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('MISSING', result.stdout)

    def test_doctor_rejects_invalid_toml(self):
        (self.bin / 'python3').symlink_to(shutil.which('python3'))
        path = self.home / 'bad.toml'
        path.write_text('[broken')
        result = self.shell('doctor_toml "$HOME/bad.toml"')
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def picker(self, input='', args=()):
        jq = shutil.which('jq')
        if not (self.bin / 'jq').exists():
            (self.bin / 'jq').symlink_to(jq)
        self.stub('herdr', '''if [ "$1" = session ]; then
  echo '{"sessions":[{"name":"default","running":true},{"name":"work","running":true}]}'
else printf 'ATTACH:%s\\n' "$@"; fi''')
        return subprocess.run(['/bin/bash', str(REPO / 'scripts/herdr-session.sh'), *args],
                              env=self.env, input=input, text=True, capture_output=True)

    def test_picker_existing_new_cancel_and_direct(self):
        result = self.picker('2\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ATTACH:work', result.stdout)
        result = self.picker('n\nside-project\n')
        self.assertIn('ATTACH:side-project', result.stdout)
        self.assertNotIn('ATTACH:', self.picker('q\n').stdout)
        result = self.picker(args=('personal',))
        self.assertIn('ATTACH:personal', result.stdout)

    def test_picker_empty_list_can_create_session(self):
        (self.bin / 'jq').symlink_to(shutil.which('jq'))
        self.stub('herdr', '''if [ "$1" = session ]; then echo '{"sessions":[]}'; else printf 'ATTACH:%s\\n' "$@"; fi''')
        result = subprocess.run(['/bin/bash', str(REPO / 'scripts/herdr-session.sh')],
                                env=self.env, input='n\nfirst\n', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ATTACH:first', result.stdout)

    def test_picker_does_not_attach_after_list_failure(self):
        (self.bin / 'jq').symlink_to(shutil.which('jq'))
        self.stub('herdr', 'exit 7')
        result = subprocess.run(['/bin/bash', str(REPO / 'scripts/herdr-session.sh')],
                                env=self.env, input='1\n', text=True, capture_output=True)
        self.assertEqual(result.returncode, 7)
        self.assertNotIn('ATTACH:', result.stdout)

    def test_picker_invalid_and_nested(self):
        for value in ['99\n', 'n\nbad name\n', '999999999999999999999999\n']:
            self.assertNotEqual(self.picker(value).returncode, 0)
        self.env['HERDR_PANE_ID'] = 'w1:p1'
        result = self.picker('1\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Detach first', result.stderr)


if __name__ == '__main__':
    unittest.main()
