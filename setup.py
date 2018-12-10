#
from distutils.core import setup
from Cython.Build import cythonize
from Cython.Compiler import Options

Options.fast_fail = True
Options.annotate = True
setup(ext_modules=cythonize('sidfam/*.pyx'))
