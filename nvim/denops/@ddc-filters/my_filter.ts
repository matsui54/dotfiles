import {
  BaseFilter,
  Candidate,
} from "https://deno.land/x/ddc_vim@v1.2.0/types.ts#^";
import {
  FilterArguments,
} from "https://deno.land/x/ddc_vim@v1.2.0/base/filter.ts#^";
import { Fzf } from "https://esm.sh/fzf@0.4.1";

// TODO: add sourceWeight => ex. vsnip += 10
type Params = {
  sourceIdxWeight: number;
  hlGroup: string;
  excludeSources: string[];
};

type sortItem = {
  item: Candidate;
  score: number;
};

export class Filter extends BaseFilter<Params> {
  filter({
    filterParams,
    completeStr,
    candidates,
  }: FilterArguments<Params>): Promise<Candidate[]> {
    let sourceIndex = -1;
    const idxMap: Record<string, number> = {};
    const toCalc: Candidate[] = [];
    const excluded: sortItem[] = [];
    for (const c of candidates) {
      // @ts-ignore: Unofficial API
      const src = c.__sourceName as string;
      if (filterParams.excludeSources.includes(src)) {
        excluded.push({
          item: c,
          score: 50 - sourceIndex * filterParams.sourceIdxWeight,
        });
      } else {
        toCalc.push(c);
      }
      if (!idxMap[src]) {
        idxMap[src] = sourceIndex;
        sourceIndex++;
      }
    }

    const fzf = new Fzf(toCalc, {
      sort: false,
      selector: (item) => item.word,
    });

    const filtered = fzf.find(completeStr).map((e) => {
      // @ts-ignore: Unofficial API
      const src = e.item.__sourceName as string;
      e.score -= idxMap[src] * filterParams.sourceIdxWeight;
      e.item.highlights = [...e.positions.values()].map((p) => ({
        col: p,
        type: "abbr",
        name: "ddc_my_filter_hl",
        "hl_group": filterParams.hlGroup,
        width: 1,
      }));
      e.item.menu = `${e.item.menu ?? ""} ${e.score}`;
      return { item: e.item, score: e.score } as sortItem;
    });
    return Promise.resolve(
      filtered.concat(excluded).sort((a, b) => b.score - a.score)
        .map((e) => e.item),
    );
  }
  params(): Params {
    return {
      sourceIdxWeight: 5,
      hlGroup: "Title",
      excludeSources: [],
    };
  }
}
