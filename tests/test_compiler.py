import importlib.util,pathlib,tempfile,unittest
spec=importlib.util.spec_from_file_location('compiler','tools/lc_compile.py');compiler=importlib.util.module_from_spec(spec);spec.loader.exec_module(compiler)
class Compiler(unittest.TestCase):
 def run_case(self,text):
  with tempfile.TemporaryDirectory() as directory:
   p=pathlib.Path(directory)/'a.toml';o=p.with_suffix('.cpp');p.write_text(text);compiler.compile_file(p,o);return o.read_text()
 def test_inheritance(self):
  out=self.run_case('format_version=2\n[workspace]\ninherit=["t","x"]\ngates=[{t="H",o=1,x=10},{o=2}]\n')
  self.assertEqual(out.count('e.type="H"'),2);self.assertEqual(out.count('e.x=10'),2)
 def test_unknown(self):
  with self.assertRaises(ValueError):self.run_case('format_version=2\n[workspace]\ngates=[{t="MAGIC",o=1}]')
 def test_dangling(self):
  with self.assertRaises(ValueError):self.run_case('format_version=2\n[workspace]\ngates=[{t="NOT",i=1,o=2}]')
 def test_recursive(self):
  with self.assertRaises(ValueError):self.run_case('format_version=2\n[workspace]\nn="SELF"\ngates=[{t="SELF"}]')
 def test_display_name_from_nodes(self):
  out=self.run_case('format_version=2\n[workspace]\ninherit=["t"]\ngates=[{t="NODE",o=1,n="BUS.D0"},{o=2,n="BUS.D1"},{t="DISPLAY",i=[1,2]}]')
  self.assertIn('e.name="BUS"',out)
 def test_multidriver(self):
  out=self.run_case('format_version=2\n[workspace]\ngates=[{t="H",o=1},{t="L",o=2},{t="BUF",i=[[1,2]],o=3}]')
  self.assertIn('e.in={1}',out)

 def test_terminal(self):
  import json
  gate={'t':'TERMINAL','i':[0]*26,'o':list(range(1,9)),'io_base':0xd010}
  def source():
   return 'format_version=2\n[workspace]\ngates=[{'+', '.join(k+'='+json.dumps(v) for k,v in gate.items())+'}]'
  self.assertIn('e.io_base=53264',self.run_case(source()))
  for value in [-4,65536,1,True]:
   gate['io_base']=value
   with self.assertRaises(ValueError):self.run_case(source())
  gate['io_base']=0xd010;gate['i']=[0]*25
  with self.assertRaises(ValueError):self.run_case(source())
