# Sphinx configuration for the Background Assets plugin docs.
# https://www.sphinx-doc.org/en/master/usage/configuration.html
# No html_static_path or html_favicon: under -W a missing static dir or favicon fails the build.

project = 'Background Assets plugin for Solar2D'
copyright = '2026, Studycat Limited'
author = 'Studycat Limited'

extensions = []

exclude_patterns = ['_build', '.venv', 'venv', 'Thumbs.db', '.DS_Store']

html_theme = 'alabaster'
html_sidebars = {'**': ['about.html', 'navigation.html', 'relations.html', 'searchbox.html']}
