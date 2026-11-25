from pathlib import Path
import runpy
import unittest
label=runpy.run_path(str(Path(__file__).resolve().parents[1]/'scripts/build-taipei-shop-floors.py'))['floor_label']

class Floors(unittest.TestCase):
    def test_posted_labels(self):
        self.assertEqual(label({'addr:floor':'２樓','level':'1'}),'2F')
        self.assertEqual(label({'addr:floor':'B1','level':'-1','level:ref':'地下１樓'}),'B1')
        self.assertEqual(label({'addr:floor':'1;2','level':'0;1'}),'1F、2F')
    def test_relative_levels_and_conflicting_or_ambiguous_sources(self):
        for tags,out in [({'level':'0'},'地面層'),({'level':'1'},'樓上'),({'level':'-1'},'地下樓層'),
                         ({'level':'0','addr:floor':'B1'},None),({'level:ref':'M','level':'1'},None),
                         ({'name':'B1 Cafe','addr:housenumber':'3'},None),({'level':'1.5'},None),
                         ({'addr:floor':'3','level:ref':'2F'},None)]:
            self.assertEqual(label(tags),out)
if __name__=='__main__':
    unittest.main()
