import {
  BaseFilter,
  Candidate,
} from "https://deno.land/x/ddc_vim@v1.2.0/types.ts#^";
import {
  FilterArguments,
  OnInitArguments,
} from "https://deno.land/x/ddc_vim@v1.2.0/base/filter.ts#^";
import { Fzf } from "https://esm.sh/fzf@0.4.1";

// TODO: add ignore => default base score: about 50
// add sourceWeight => ex. vsnip += 10
type Params = { sourceIdxWeight: number; hlGroup: string };

export class Filter extends BaseFilter<Params> {
  async onInit(args: OnInitArguments<Params>): Promise<void> {
  }
  filter({
    filterParams,
    completeStr,
    candidates,
  }: FilterArguments<Params>): Promise<Candidate[]> {
    const sources: string[] = [];
    const fzf = new Fzf(candidates, {
      sort: false,
      selector: (item) => item.word,
    });
    let sourceIndex = -1;
    return Promise.resolve(
      fzf.find(completeStr).map((e) => {
        // @ts-ignore:
        const src = e.item.__sourceName as string;
        if (!sources.includes(src)) {
          if (src == "nvim-lsp") {
            console.log(e.item.word);
          }
          sources.push(src);
          sourceIndex++;
        }
        e.score -= sourceIndex * filterParams.sourceIdxWeight;
        e.item.highlights = [...e.positions.values()].map((p) => ({
          col: p,
          type: "abbr",
          name: "ddc_my_filter_hl",
          "hl_group": filterParams.hlGroup,
          width: 1,
        }));
        e.item.menu = `${e.item.menu ?? ""} ${e.score}`;
        return e;
      }).sort((a, b) => b.score - a.score).map((e) => e.item),
    );
  }
  params(): Params {
    return {
      sourceIdxWeight: 20,
      hlGroup: "Title",
    };
  }
}
