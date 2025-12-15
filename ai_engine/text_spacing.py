# ai_engine/text_spacing.py
####### 띄어쓰기 조정 #######

from kiwipiepy import Kiwi

_kiwi = Kiwi()

def fix_spacing(text: str) -> str:
    return _kiwi.space(text)
