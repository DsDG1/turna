"""Unit tests for CourseScaffold."""
import shutil
import tempfile
import unittest
from pathlib import Path

from src.backend.course_scaffold import CourseScaffold


class TestCourseScaffold(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="test_scaffold_"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_init_new_raises_when_non_empty(self):
        target = self.tmp / "existing"
        target.mkdir()
        (target / "dummy.txt").write_text("hello", encoding="utf-8")

        with self.assertRaises(FileExistsError):
            CourseScaffold.init_new(target, {})

    def test_init_new_creates_course_structure(self):
        target = self.tmp / "my_course"
        loaded_dir = None

        def fake_load(cdir):
            nonlocal loaded_dir
            loaded_dir = cdir

        meta = {
            "display_name": "Test Course",
            "language": "en",
            "source_language": "Chinese",
            "section_count": 2,
            "lessons_per_unit": 2,
        }

        CourseScaffold.init_new(target, meta, load_fn=fake_load)

        self.assertEqual(loaded_dir, target)
        self.assertTrue((target / "index.json").is_file())
        self.assertTrue((target / "sections" / "section1.json").is_file())
        self.assertTrue((target / "sections" / "section2.json").is_file())
        self.assertTrue((target / "vocab.json").is_file())
        self.assertTrue((target / "expressions.json").is_file())
        self.assertTrue((target / "grammar_points.json").is_file())

    def test_sample_vocab(self):
        vocab_en = CourseScaffold.sample_vocab("en")
        self.assertTrue(len(vocab_en) > 0)
        self.assertIn("id", vocab_en[0])
        self.assertIn("term", vocab_en[0])

        vocab_other = CourseScaffold.sample_vocab("tr")
        self.assertTrue(len(vocab_other) > 0)

    def test_sample_expressions(self):
        expr = CourseScaffold.sample_expressions("en")
        self.assertTrue(len(expr) > 0)
        self.assertIn("id", expr[0])

    def test_sample_grammar_points(self):
        gp = CourseScaffold.sample_grammar_points("en")
        self.assertTrue(len(gp) > 0)
        self.assertIn("id", gp[0])

    def test_build_sample_intro_lesson(self):
        lesson = CourseScaffold.build_sample_intro_lesson("Chinese", "en")
        self.assertEqual(lesson["id"], "section1-u1-l1")
        self.assertIn("subLessons", lesson["content"])


if __name__ == "__main__":
    unittest.main()
