#
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
from Cython.Compiler import Options

Options.fast_fail = True
Options.annotate = True

extensions = [
    Extension(
        '*', ['sidfam/*.pyx'],
        extra_compile_args=[
            '-std=c++14',
            '-fopenmp',
        ],
        extra_link_args=[
            '-fopenmp',
            # '-L/usr/local/opt/libomp/lib',
            # '-I/usr/local/opt/libomp/include'
        ],
    )
]

setup(ext_modules=cythonize(extensions))
