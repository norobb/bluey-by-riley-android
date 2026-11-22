import unittest

from bluey.setup import UUID, with_extension


class SetupTest(unittest.TestCase):
    def test_adds_extension(self):
        self.assertEqual(with_extension("@as []\n"), [UUID])
        self.assertEqual(with_extension("['a@b']"), ["a@b", UUID])

    def test_keeps_existing(self):
        self.assertIsNone(with_extension(f"['a@b', '{UUID}']"))


if __name__ == "__main__":
    unittest.main()
