# Sphinx configuration for the Background Assets plugin docs.
# https://www.sphinx-doc.org/en/master/usage/configuration.html
# Theme: Furo. Extensions: sphinx-copybutton (copy button on code blocks), sphinx-design (cards and tabs) and
# sphinxext-opengraph (link previews).
# Their versions are pinned in requirements.txt and docs/requirements.txt, which stay identical.

project = 'Background Assets plugin for Solar2D'
copyright = '2026, Studycat Limited'
author = 'Studycat Limited'

extensions = ['sphinx_copybutton', 'sphinx_design', 'sphinxext.opengraph']

exclude_patterns = ['_build', '.venv', 'venv', 'Thumbs.db', '.DS_Store']

html_theme = 'furo'
html_title = 'Background Assets for Solar2D'
html_static_path = ['_static']
html_favicon = '_static/logo.svg'
html_css_files = ['custom.css']

html_theme_options = {
    'light_logo': 'logo.svg',
    'dark_logo': 'logo.svg',
    'sidebar_hide_name': False,
    'navigation_with_keys': True,
    'source_repository': 'https://github.com/depilz/solar2d-plugin-background-assets/',
    'source_branch': 'main',
    'source_directory': 'docs/',
    'light_css_variables': {
        'color-brand-primary': '#1f6feb',
        'color-brand-content': '#1f6feb',
    },
    'dark_css_variables': {
        'color-brand-primary': '#58a6ff',
        'color-brand-content': '#58a6ff',
    },
    'footer_icons': [
        {
            'name': 'GitHub',
            'url': 'https://github.com/depilz/solar2d-plugin-background-assets',
            'html': '<svg stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 16 16"><path fill-rule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"></path></svg>',
            'class': '',
        },
    ],
}

# Copy only the code, never a shell prompt or output line.
copybutton_exclude = '.linenos, .gp, .go'

# Link previews. On Read the Docs the site URL comes from the build; og-card.png is og-card.svg exported at 1200x630.
ogp_site_name = 'Background Assets for Solar2D'
ogp_image = '_static/og-card.png'
ogp_image_alt = 'Background Assets for Solar2D'
ogp_social_cards = {'enable': False}
