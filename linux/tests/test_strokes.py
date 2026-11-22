import unittest

from bluey.ai import parse_strokes


class StrokesTest(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(parse_strokes(["100,200 150.5,180", "5,5"]), [[(100, 200), (150.5, 180)], [(5, 5), (5, 5)]])

    def test_garbage(self):
        self.assertEqual(parse_strokes("100,200"), [])
        self.assertEqual(parse_strokes([None, "abc"]), [])
        self.assertEqual(len(parse_strokes([" ".join(["1,1"] * 999)])[0]), 400)


if __name__ == "__main__":
    unittest.main()
