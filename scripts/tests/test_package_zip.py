import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('package_zip', ROOT / 'scripts/package-zip.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
NOTES = '2026-10-26 (1차 배포)\n\n- 도구 선택을 추가했습니다.\n- 화면 잘림을 수정했습니다.\n'



class PackageZipTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.app = self.root / 'PokeTokenBar.app'
        self.exe = self.app / 'Contents/MacOS/PokeTokenBar'
        self.exe.parent.mkdir(parents=True)
        self.exe.write_bytes(b'original executable bytes')
        self.exe.chmod(0o755)
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'2.5.6','CFBundleExecutable':'PokeTokenBar'}))
        self.notes = self.root / 'notes.txt'
        self.notes.write_text(NOTES, encoding='utf-8')
        self.output = self.root / 'release.zip'

    def test_missing_or_empty_notes_do_not_create_a_zip(self):
        self.notes.unlink()
        with self.assertRaises(FileNotFoundError):
            package.package_zip(self.app, self.notes, self.output)
        self.notes.write_text('')
        with self.assertRaises(ValueError):
            package.package_zip(self.app, self.notes, self.output)
        self.assertFalse(self.output.exists())

    def test_date_headers_require_bullets_and_descending_release_numbers(self):
        invalid = ['', '2026-10-26 (1차 배포)\n', '- 제목 없는 변경사항',
                   '2026-02-30 (1차 배포)\n- 잘못된 날짜', '2026-10-26 (0차 배포)\n- 잘못된 회차',
                   NOTES + '2026-10-26 (1차 배포)\n- 중복 회차',
                   NOTES + '2026-10-26 (2차 배포)\n', NOTES + '2026-10-26 (2차 배포)\n- 오름차순', NOTES + '별도 설명 문구', NOTES + '2026-10-27 (1차 배포)\n- 날짜 오름차순']
        for text in invalid:
            with self.subTest(text=text):
                self.notes.write_text(text)
                with self.assertRaises(ValueError):
                    package.read_notes(self.notes)
        valid = '2026-10-27 (1차 배포)\n\n- 최신 날짜 배포\n\n2026-10-26 (10차 배포)\n\n- 최신 수정\n\n2026-10-26 (2차 배포)\n\n- 추가 수정\n\n' + NOTES
        self.notes.write_text(valid)
        self.assertEqual(package.read_notes(self.notes), valid)

    @unittest.skipUnless(shutil.which('ditto'), 'macOS ditto required')
    def test_real_zip_contains_utf8_notes_beside_unchanged_app(self):
        original = {str(p.relative_to(self.app)):p.read_bytes() for p in self.app.rglob('*') if p.is_file()}
        result = package.package_zip(self.app, self.notes, self.output)
        with zipfile.ZipFile(self.output) as archive:
            self.assertIsNone(archive.testzip())
            text = archive.read('Release Notes.txt').decode('utf-8')
            self.assertEqual(text, NOTES)
            metadata = json.loads(archive.read('Release Metadata.json'))
            self.assertEqual(metadata['version'], '2.5.6')
            self.assertEqual(metadata['timezone'], 'Asia/Seoul')
            self.assertEqual(metadata['executableSHA256'], hashlib.sha256(self.exe.read_bytes()).hexdigest())
            for path, data in original.items():
                self.assertEqual(archive.read('PokeTokenBar.app/' + path), data)
            self.assertTrue((archive.getinfo('PokeTokenBar.app/Contents/MacOS/PokeTokenBar').external_attr >> 16) & 0o111)
        self.assertEqual(result['sha256'], hashlib.sha256(self.output.read_bytes()).hexdigest())
        self.assertEqual({str(p.relative_to(self.app)):p.read_bytes() for p in self.app.rglob('*') if p.is_file()}, original)

    def test_existing_output_is_preserved(self):
        self.output.write_bytes(b'keep original')
        with self.assertRaises(FileExistsError):
            package.package_zip(self.app, self.notes, self.output)
        self.assertEqual(self.output.read_bytes(), b'keep original')

    def test_invalid_output_path_is_rejected_before_packaging(self):
        for output in (self.root / 'not-a-zip.txt', self.app / 'recursive.zip'):
            with self.subTest(output=output):
                with self.assertRaises(ValueError):
                    package.package_zip(self.app, self.notes, output)
                self.assertFalse(output.exists())

    def test_failed_archiver_does_not_publish_partial_output(self):
        with patch.object(package.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'ditto')):
            with self.assertRaises(subprocess.CalledProcessError):
                package.package_zip(self.app, self.notes, self.output)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob('.ptb-package-*')))

    def test_public_release_uses_the_mandatory_notes_packager(self):
        script = (ROOT / 'scripts/release.sh').read_text()
        self.assertIn('scripts/package-zip.py --app build/PokeTokenBar.app --notes "$ZIP_NOTES_FILE"', script)
        self.assertNotIn('ditto -c -k --keepParent build/PokeTokenBar.app build/PokeTokenBar.zip', script)


if __name__ == '__main__':
    unittest.main()
