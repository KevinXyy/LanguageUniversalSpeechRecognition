import sys
languages = sys.argv[1]
lang_list = languages.split()
for lang in lang_list:
    src_lang = "data/{}/local/dict".format(lang)
    src_lex = "{}/"