import unittest

from arr_provision.common import arr_api_base, read_key_file, title_case_service


class CommonHelpersTest(unittest.TestCase):
    def test_arr_api_base(self) -> None:
        self.assertEqual(arr_api_base("127.0.0.1", 5003, "v3"), "http://127.0.0.1:5003/api/v3")

    def test_title_case_service(self) -> None:
        self.assertEqual(title_case_service("sonarr"), "Sonarr")

    def test_read_key_file_missing(self) -> None:
        self.assertIsNone(read_key_file("/definitely/missing/key"))


if __name__ == "__main__":
    unittest.main()