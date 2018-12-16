#
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
from Cython.Compiler import Options

Options.fast_fail = True
Options.annotate = True

extensions = [
    Extension('*', ['sidfam/*.pyx'], extra_compile_args=['-std=c++14', '-Og'])
]

setup(ext_modules=cythonize(extensions))
