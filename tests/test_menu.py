"""Scripted menu input, temporary state and mocked side effects; no installations."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class Menu(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='mac-setup-menu-test-')
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), MAC_SETUP_LIB='1',
                        PATH=f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin')
        for key in ('MAC_SETUP_MODE', 'MAC_SETUP_COMPONENTS', 'MAC_SETUP_PULLED', 'BASH_ENV'):
            self.env.pop(key, None)
        self.record = self.home / '.config/mac-setup/selection'
        # Any accidental attempt at an external installation or system write fails.
        for command in ('brew', 'curl', 'defaults'):
            self.stub(command, 'echo UNEXPECTED-SYSTEM-CALL >&2; exit 99')

    def tearDown(self):
        self.tmp.cleanup()

    def stub(self, name, code):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + code + '\n')
        path.chmod(0o755)

    def shell(self, script, input=''):
        return subprocess.run(['/bin/bash', '-c', 'source ./install.sh\n' + script],
                              cwd=REPO, env=self.env, input=input, text=True,
                              capture_output=True, timeout=10)

    def flow(self, input='', args=''):
        return self.shell('''menu_read() { IFS= read -r REPLY; }
ensure_repo_link() { echo MUTATE:pointer; }
converge_links() { echo MUTATE:links; }
ensure_zprofile_guard() { echo MUTATE:guard; }
bootstrap_homebrew() { echo MUTATE:brew; }
apply_components() { echo "APPLY:$COMPONENTS"; echo "AGENTS:$ITEMS_AGENTS"; }
doctor() { echo HEALTH; }
main ''' + args, input)

    def save_record(self, content):
        self.record.parent.mkdir(parents=True, exist_ok=True)
        self.record.write_text(content)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('UNEXPECTED-SYSTEM-CALL', result.stderr)

    def test_quit_invalid_input_and_eof_have_no_writes(self):
        for input in ('q\n', 'wat\nq\n', '3\nq\n', ''):
            with self.subTest(input=input):
                result = self.flow(input)
                self.assertNotIn('MUTATE:', result.stdout)
                self.assertNotIn('APPLY:', result.stdout)
                self.assertFalse(self.record.exists())

    def test_partial_cancel_before_review_changes_nothing(self):
        result = self.flow('5\n\nq\n', '--mode partial')
        self.assert_ok(result)
        self.assertNotIn('MUTATE:', result.stdout)
        self.assertFalse(self.record.exists())

    def test_custom_agent_selection_is_reviewed_saved_and_replayed(self):
        result = self.flow('2\n5\n\nnone\n2\n\ni\n')
        self.assert_ok(result)
        self.assertIn('APPLY:agents', result.stdout)
        self.assertIn('AGENTS:codex', result.stdout)
        self.assertLess(result.stdout.index('Review this Mac'), result.stdout.index('MUTATE:'))
        self.assertEqual(self.record.read_text(), 'version=2\ncomponents=agents\nitems.agents=codex\n')
        replay = self.flow(args='reapply')
        self.assert_ok(replay)
        self.assertIn('AGENTS:codex', replay.stdout)

    def test_full_review_and_unattended_full_keep_legacy_record(self):
        for input, args in [('3\ni\n', ''), ('', '--mode full')]:
            with self.subTest(args=args):
                result = self.flow(input, args)
                self.assert_ok(result)
                self.assertEqual(self.record.read_text(), 'mode=full\n')

    def test_saved_choices_are_preselected_and_back_returns_main(self):
        self.save_record('version=2\ncomponents=agents\nitems.agents=codex\n')
        result = self.flow('2\nback\nq\n')
        self.assert_ok(result)
        self.assertIn('[x] Agent CLIs', result.stdout)
        self.assertNotIn('MUTATE:', result.stdout)
        self.assertEqual(self.record.read_text(), 'version=2\ncomponents=agents\nitems.agents=codex\n')

    def test_checklist_deduplicates_and_rejects_entire_invalid_input(self):
        result = self.shell('''menu_read() { IFS= read -r REPLY; }
CHECKED=''
menu_checklist test $'one|First\ntwo|Second'
echo "SELECTED:$CHECKED"''', '1 1\n2 99\n999999999999999999999999999\n\n')
        self.assert_ok(result)
        self.assertIn('SELECTED:one', result.stdout)
        self.assertIn('Invalid selection; nothing changed.', result.stdout)

    def test_health_and_relink_routes_skip_homebrew(self):
        for action in ('4', '5'):
            with self.subTest(action=action):
                result = self.flow(action + '\n')
                self.assert_ok(result)
                self.assertIn('HEALTH', result.stdout)
                self.assertNotIn('MUTATE:brew', result.stdout)
                if action == '4':
                    self.assertNotIn('MUTATE:', result.stdout)

    def test_bad_arguments_and_corrupt_records_stop_before_writes(self):
        for args in ('--mode', '--mode wrong', '--unknown', 'unknown'):
            with self.subTest(args=args):
                result = self.flow(args=args)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('MUTATE:', result.stdout)
        for record in ('version=2\ncomponents=agents\nitems.agents=unknown\n',
                       'components=agents\ncomponents=macos\n',
                       'version=2\ncomponents=agents\nitems.agents=$(touch /tmp/not-executed)\n'):
            with self.subTest(record=record):
                self.save_record(record)
                result = self.flow(args='reapply')
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('MUTATE:', result.stdout)

    def test_one_off_groups_leave_saved_record_unchanged_and_deduplicate(self):
        self.save_record('version=2\ncomponents=agents\nitems.agents=codex\n')
        result = self.flow(args='agents agents')
        self.assert_ok(result)
        self.assertIn('APPLY:agents\n', result.stdout)
        self.assertIn('AGENTS:*', result.stdout)
        self.assertEqual(self.record.read_text(), 'version=2\ncomponents=agents\nitems.agents=codex\n')

    def test_codex_only_does_not_install_other_agents_or_link_claude(self):
        self.stub('brew', 'echo "BREW:$*" >> "$HOME/brew-calls"')
        result = self.shell('ITEMS_AGENTS=codex\ncomp_agents')
        self.assert_ok(result)
        self.assertEqual((self.home / 'brew-calls').read_text(), 'BREW:list codex\n')
        self.assertFalse((self.home / '.claude').exists())
        self.assertFalse((self.home / '.zshrc.local').exists())

    def test_miniforge_only_does_not_set_up_nvm(self):
        binary = self.home / 'miniforge3/bin/conda'
        binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/bash\nexit 0\n')
        binary.chmod(0o755)
        result = self.shell('ITEMS_DEVTOOLS=miniforge\ncomp_devtools')
        self.assert_ok(result)
        self.assertIn('conda initialize', (self.home / '.zshrc.local').read_text())
        self.assertNotIn('mac-setup nvm', (self.home / '.zshrc.local').read_text())
        self.assertFalse((self.home / '.nvm').exists())

    def test_nvm_only_does_not_set_up_miniforge(self):
        script = self.home / '.nvm/nvm.sh'
        script.parent.mkdir()
        script.write_text('nvm() { echo v22.0.0; }\n')
        result = self.shell('ITEMS_DEVTOOLS=nvm\ncomp_devtools')
        self.assert_ok(result)
        self.assertIn('mac-setup nvm', (self.home / '.zshrc.local').read_text())
        self.assertNotIn('conda initialize', (self.home / '.zshrc.local').read_text())
        self.assertFalse((self.home / 'miniforge3').exists())

    def test_grok_only_uses_local_init_and_does_not_link_claude(self):
        binary = self.home / '.grok/bin/grok'
        binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/bash\nexit 0\n')
        binary.chmod(0o755)
        fixture = self.home / 'fixture/home/zshrc'
        fixture.parent.mkdir(parents=True)
        fixture.write_text('# shell fixture\n')
        result = self.shell('REPO="$HOME/fixture"\nITEMS_AGENTS=grok\ncomp_agents')
        self.assert_ok(result)
        self.assertIn('grok installer', (self.home / '.zshrc.local').read_text())
        self.assertFalse((self.home / '.claude').exists())

    def test_herdr_only_does_not_install_terminals_or_write_defaults(self):
        self.stub('brew', 'echo "BREW:$*" >> "$HOME/brew-calls"')
        result = self.shell('ITEMS_GHOSTTY=herdr\ncomp_ghostty')
        self.assert_ok(result)
        self.assertEqual((self.home / 'brew-calls').read_text(), 'BREW:list herdr\nBREW:list jq\n')
        self.assertTrue((self.home / '.config/herdr/config.toml').is_symlink())
        self.assertFalse((self.home / '.config/ghostty').exists())
        self.assertFalse((self.home / '.config/alacritty').exists())

    def test_brewfile_subset_excludes_unselected_packages(self):
        jq = shutil.which('jq')
        self.assertIsNotNone(jq)
        (self.bin / 'jq').symlink_to(jq)
        self.stub('brew', '''case "$1" in
list|tap) exit 0 ;;
info) echo '{"casks":[]}' ;;
bundle) for arg in "$@"; do case "$arg" in --file=*) cat "${arg#--file=}" > "$HOME/applied-Brewfile" ;; esac; done ;;
*) exit 99 ;;
esac''')
        result = self.shell("ITEMS_APPS='cask:firefox brew:gh'\ncomp_apps")
        self.assert_ok(result)
        lines = (self.home / 'applied-Brewfile').read_text().splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(any(line.startswith('brew "gh"') for line in lines))
        self.assertTrue(any(line.startswith('cask "firefox"') for line in lines))

    def test_diagnostics_follow_saved_agent_filter(self):
        self.save_record('version=2\ncomponents=agents\nitems.agents=codex\n')
        self.stub('brew', 'exit 0')
        self.stub('codex', 'echo codex-test')
        result = self.shell('doctor_environment')
        self.assert_ok(result)
        self.assertNotIn('MISSING', result.stdout)

    def test_diagnostics_follow_saved_brewfile_filter(self):
        self.save_record('version=2\ncomponents=apps\nitems.apps=brew:gh cask:firefox\n')
        self.stub('brew', 'echo "gh 1.0"')
        self.stub('gh', 'echo gh-test')
        self.stub('jq', 'echo jq-test')
        result = self.shell('doctor_environment')
        self.assert_ok(result)
        self.assertNotIn('MISSING', result.stdout)
        self.assertNotIn('Brewfile formula missing', result.stdout)
        self.assertNotIn('google-chrome', result.stdout)

    def test_fresh_menu_update_and_reapply_do_not_pull_or_write(self):
        result = self.flow('1\n6\nq\n')
        self.assert_ok(result)
        self.assertIn('save a setup first', result.stdout)
        self.assertNotIn('MUTATE:', result.stdout)

    def test_invalid_review_choice_keeps_review_open(self):
        result = self.flow('2\n7\n\nwrong\ni\n')
        self.assert_ok(result)
        self.assertEqual(result.stdout.count('Choose installation groups'), 2)
        self.assertIn('Choose i, b, or q.', result.stdout)
        self.assertIn('APPLY:macos', result.stdout)

    def test_subset_failure_recommends_saved_replay(self):
        result = self.shell('''COMPONENTS=agents; ITEMS_AGENTS=codex
comp_agents() { return 9; }
apply_components''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('re-run: ./install.sh reapply', result.stdout)

    def test_atomic_selection_save_failure_keeps_old_record(self):
        self.save_record('mode=full\n')
        result = self.shell("MODE=partial; COMPONENTS=agents; ITEMS_AGENTS=codex\natomic_rename() { return 9; }\nsave_selection")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.record.read_text(), 'mode=full\n')

    def test_menu_update_reexec_uses_action_argument(self):
        self.save_record('mode=full\n')
        result = self.shell('''menu_read() { IFS= read -r REPLY; }
git() { case "$*" in *ls-files*) return 0 ;; *pull*) return 0 ;; *) command git "$@" ;; esac; }
exec() { printf 'EXEC:%s\\n' "$@"; exit 0; }
main''', '1\n')
        self.assert_ok(result)
        self.assertIn('EXEC:update', result.stdout)
        self.assertEqual(result.stdout.count('Choice:'), 1)


if __name__ == '__main__':
    unittest.main()
