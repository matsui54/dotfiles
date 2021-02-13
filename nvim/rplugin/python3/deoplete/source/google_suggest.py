from deoplete.base.source import Base
import requests


class Source(Base):

    def __init__(self, vim):
        super().__init__(vim)

        self.name = 'google'
        self.mark = '[g]'
        self.matchers = []
        self.sorters = []
        self.is_volatile = True
        self.is_skip_langmap = False
        self.rank = 1000
        self.filetypes = ['google']
        self.base_url = '''
        https://www.google.com/complete/search?hl=ja&client=chrome&q=
        '''

    def get_complete_position(self, context):
        return 0

    def gather_candidates(self, context):
        candidates = []

        input = context['complete_str']
        try:
            buf = requests.get(
                self.base_url + input, timeout=(3.0, 0.9)
            ).json()
        except OSError:
            return []
        except requests.exceptions.Timeout:
            return []

        for i in buf[1]:
            candidates.append({
                'word': i
            })
        return candidates
