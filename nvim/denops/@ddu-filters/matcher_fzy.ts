import {
  hasMatch,
  positions,
  score,
} from "https://raw.githubusercontent.com/jhawthorn/fzy.js/master/index.js";
import {
  BaseFilter,
  DduItem,
} from "https://deno.land/x/ddu_vim@v0.14/types.ts#^";
import { Denops } from "https://deno.land/x/ddu_vim@v0.14/deps.ts#^";

type Params = {
  hlGroup: string;
};

type SortItem = {
  score: number;
  item: DduItem;
};

export class Filter extends BaseFilter<Params> {
  filter(args: {
    denops: Denops;
    input: string;
    items: DduItem[];
    filterParams: Params;
  }): Promise<DduItem[]> {
    const input = args.input;
    const filtered = args.items.filter((i) => hasMatch(input, i.word));
    if (filtered.length > 10000) {
      return Promise.resolve(filtered);
    }
    return Promise.resolve(
      filtered.map((
        c,
      ) => ({ score: score(input, c.word), item: c } as SortItem))
        .sort((a, b) => b.score - a.score).map((c) => {
          const highlights = positions(input, c.item.word).map((p) => ({
            col: p + 1,
            type: "abbr",
            name: "ddu_fzy_hl",
            "hl_group": args.filterParams.hlGroup,
            width: 1,
          }));
          if (c.item.highlights) {
            c.item.highlights = c.item.highlights.concat(highlights);
          } else {
            c.item.highlights = highlights;
          }
          return c.item;
        }),
    );
  }

  params(): Params {
    return {
      hlGroup: "Title",
    };
  }
}
