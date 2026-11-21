"""Tests for fetch_landmarks.py. Run: python3 -m unittest discover -s scripts"""

import itertools
import unittest

import fetch_landmarks


def record(category: str) -> dict:
    return {"id": "Q1", "name": "Example", "category": category}


class MergeLandmarkTests(unittest.TestCase):
    def merged_category(self, categories: list[str]) -> str:
        landmarks: dict[str, dict] = {}
        for category in categories:
            fetch_landmarks.merge_landmark(landmarks, record(category))
        return landmarks["Q1"]["category"]

    def test_multi_type_item_gets_same_category_in_any_row_order(self):
        categories = ["landmark", "stadium", "museum", "university"]
        for order in itertools.permutations(categories):
            with self.subTest(order=order):
                self.assertEqual(self.merged_category(list(order)), "museum")

    def test_specific_category_beats_generic_listed_earlier(self):
        # "national monument" (landmark) precedes "nature reserve" in LANDMARK_TYPES.
        self.assertEqual(self.merged_category(["nationalPark", "landmark"]), "nationalPark")
        self.assertEqual(self.merged_category(["landmark", "nationalPark"]), "nationalPark")

    def test_every_category_has_a_priority(self):
        categories = {cat for _, _, cat in fetch_landmarks.LANDMARK_TYPES}
        self.assertEqual(set(fetch_landmarks.CATEGORY_PRIORITY), categories)
        self.assertEqual(
            max(fetch_landmarks.CATEGORY_PRIORITY, key=fetch_landmarks.CATEGORY_PRIORITY.get),
            "landmark",
        )


if __name__ == "__main__":
    unittest.main()
