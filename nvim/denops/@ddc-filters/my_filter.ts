import { fn } from "https://deno.land/x/ddc_vim@v1.3.0/deps.ts";
import {
  BaseFilter,
  Candidate,
} from "https://deno.land/x/ddc_vim@v1.2.0/types.ts#^";
import {
  FilterArguments,
} from "https://deno.land/x/ddc_vim@v1.2.0/base/filter.ts#^";
import { Fzf } from "https://esm.sh/fzf@0.4.1";

const LINES_MAX = 150;
const SCORE_SAME_LINE = 5;

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
  events = ["InsertEnter"] as never[];

  private cache: Record<string, number> = {};

  async onEvent({
    denops,
    options,
  }: FilterArguments<Params>): Promise<void> {
    const maxSize = LINES_MAX;
    const currentLine = (await denops.call("line", ".")) as number;
    const minLines = Math.max(1, currentLine - maxSize);
    const maxLines = Math.min(
      await fn.line(denops, "$"),
      currentLine + maxSize,
    );

    this.cache = {};
    let linenr = minLines;
    const pattern = new RegExp(options.keywordPattern, "gu");
    for (const line of await fn.getline(denops, minLines, maxLines)) {
      for (const match of line.matchAll(pattern)) {
        const word = match[0];
        if (
          word in this.cache &&
          Math.abs(this.cache[word] - currentLine) <=
            Math.abs(linenr - currentLine)
        ) {
          continue;
        }
        this.cache[word] = linenr;
      }
      linenr += 1;
    }
  }

  async filter({
    denops,
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
      return { item: e.item, score: e.score } as sortItem;
    });
    const all = filtered.concat(excluded);
    const linenr = await fn.line(denops, ".");
    all.map((i) => {
      const lWord = this.cache[i.item.word];
      if (lWord && Math.abs(lWord - linenr) < LINES_MAX) {
        i.score += (1 - Math.abs(lWord - linenr) / LINES_MAX) *
          SCORE_SAME_LINE;
      }
      // i.item.menu = `${i.item.menu ?? ""} ${i.score}`;
    });
    return Promise.resolve(
      all.sort((a, b) => b.score - a.score)
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
