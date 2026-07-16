import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import c200_keeper


class KeeperTests(unittest.TestCase):
    def test_capture_angle_frame(self):
        content = "[config]\nframeMode=1\nzoom=175\npan=-3600\ntilt=7200\nfovValue=78\n"
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "anker.ini"
            state_file = Path(directory) / "state.json"
            source.write_text(content)
            with patch.object(c200_keeper, "ANKER_STATE", source), patch.object(c200_keeper, "STATE_FILE", state_file), patch.object(c200_keeper, "CONFIG_DIR", Path(directory)):
                state = c200_keeper.capture_anker_state()
                self.assertEqual((state["mode"], state["zoom"], state["pan"], state["tilt"]), ("angle-frame", 175, -3600, 7200))

    def test_apply_uses_zoom_and_frame(self):
        calls = []
        class FakeCamera:
            def __enter__(self): return self
            def __exit__(self, *_): pass
            def set_pan_tilt(self, pan, tilt): calls.append(("pan_tilt", pan, tilt))
            def set_zoom(self, zoom): calls.append(("zoom", zoom))
        with patch.object(c200_keeper, "C200", FakeCamera):
            c200_keeper.apply_state({"mode": "angle-frame", "zoom": 200, "pan": 1, "tilt": 2})
        self.assertEqual(calls, [("pan_tilt", 1, 2), ("zoom", 200)])


if __name__ == "__main__":
    unittest.main()
