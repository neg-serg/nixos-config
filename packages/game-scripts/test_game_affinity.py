import os
import sys
import unittest
from unittest.mock import patch, mock_open

# Import the module under test
# We need to add the current directory to sys.path to import it
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import game_affinity_exec as gae


class TestGameAffinityExec(unittest.TestCase):

    def test_parse_cpuset_simple(self):
        self.assertEqual(gae.parse_cpuset("0,1,2"), [0, 1, 2])

    def test_parse_cpuset_range(self):
        self.assertEqual(gae.parse_cpuset("0-3"), [0, 1, 2, 3])

    def test_parse_cpuset_mixed(self):
        self.assertEqual(gae.parse_cpuset("0,2-4,6"), [0, 2, 3, 4, 6])

    def test_parse_cpuset_empty(self):
        self.assertEqual(gae.parse_cpuset(""), [])

    def test_parse_size(self):
        self.assertEqual(gae.parse_size("1024"), 1024)
        self.assertEqual(gae.parse_size("1K"), 1024)
        self.assertEqual(gae.parse_size("1M"), 1024 * 1024)
        self.assertEqual(gae.parse_size("1G"), 1024 * 1024 * 1024)
        self.assertEqual(gae.parse_size("invalid"), 0)

    @patch("os.listdir")
    @patch("builtins.open", new_callable=mock_open)
    @patch("os.path.join")
    def test_l3_groups(self, mock_join, mock_file, mock_listdir):
        # Setup mock filesystem
        mock_listdir.return_value = ["cpu0", "cpu1", "cpu2", "cpu3", "other"]

        # Mock path joins to return predictable strings
        def side_effect_join(*args):
            return "/".join(args)

        mock_join.side_effect = side_effect_join

        # Define file contents
        file_contents = {
            "/sys/devices/system/cpu/cpu0/cache/index3/size": "32M",
            "/sys/devices/system/cpu/cpu0/cache/index3/shared_cpu_list": "0-1",
            "/sys/devices/system/cpu/cpu1/cache/index3/size": "32M",
            "/sys/devices/system/cpu/cpu1/cache/index3/shared_cpu_list": "0-1",
            "/sys/devices/system/cpu/cpu2/cache/index3/size": "96M",
            "/sys/devices/system/cpu/cpu2/cache/index3/shared_cpu_list": "2-3",
            "/sys/devices/system/cpu/cpu3/cache/index3/size": "96M",
            "/sys/devices/system/cpu/cpu3/cache/index3/shared_cpu_list": "2-3",
        }

        def side_effect_open(file, mode="r"):
            content = file_contents.get(file)
            if content is None:
                raise FileNotFoundError(file)
            return mock_open(read_data=content).return_value

        mock_file.side_effect = side_effect_open

        groups = gae.l3_groups()

        # Expected: [(32M, [0, 1]), (96M, [2, 3])]
        # Note: 32M = 33554432, 96M = 100663296
        expected = [(33554432, [0, 1]), (100663296, [2, 3])]

        # Sort by size to compare
        groups.sort()
        expected.sort()

        self.assertEqual(groups, expected)

    @patch("game_affinity_exec.l3_groups")
    def test_auto_cpuset_picks_largest(self, mock_l3):
        # Mock L3 groups: one small (standard CCD), one large (V-Cache CCD)
        mock_l3.return_value = [
            (32 * 1024 * 1024, [0, 1, 2, 3]),
            (96 * 1024 * 1024, [4, 5, 6, 7]),
        ]

        cpus = gae.auto_cpuset()
        self.assertEqual(cpus, [4, 5, 6, 7])

    @patch("game_affinity_exec.l3_groups")
    @patch("os.environ.get")
    def test_auto_cpuset_limit(self, mock_env, mock_l3):
        mock_l3.return_value = [(96 * 1024 * 1024, [0, 1, 2, 3, 4, 5, 6, 7])]
        mock_env.return_value = "4"  # Limit to 4 cores

        cpus = gae.auto_cpuset()
        self.assertEqual(cpus, [0, 1, 2, 3])


if __name__ == "__main__":
    # Rename the file import to match the module name if we were running it directly
    # But here we imported it as gae
    unittest.main()
