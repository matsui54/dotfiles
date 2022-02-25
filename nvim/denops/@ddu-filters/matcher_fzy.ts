import {
  hasMatch,
  positions,
  score,
} from "https://raw.githubusercontent.com/jhawthorn/fzy.js/master/index.js";
import {
  BaseFilter,
  DduItem,
  SourceOptions,
} from "https://deno.land/x/ddu_vim@v0.1.0/types.ts";
import { Denops } from "https://deno.land/x/ddu_vim@v0.1.0/deps.ts";

type Params = Record<never, never>;

/*
var query = "amuser";

// fzy.js includes `hasMatch` which can be used for filtering
list = list.filter((s) => fzy.hasMatch(s));

// Sort by fzy's scoring, descending (higher scores are better matches)
list = sortBy(list, (s) => -fzy.score(query, s));

// Select only the first 10 results
list.slice(0, 10);

// Print out our results with matched positions
list.forEach((s) => {
	var padded = "";
	var p = fzy.positions(query, s);
	for(var i = 0; i < query.length; i++) {
		padded = padded.padEnd(p[i], ' ') + query[i];
	}

	console.log(s);
	console.log(padded);
	console.log("");
});
*/
type SortItem = {
  score: number;
  item: DduItem;
};

export class Filter extends BaseFilter<Params> {
  private cache: Record<string, DduItem>;
  filter(args: {
    denops: Denops;
    sourceOptions: SourceOptions;
    input: string;
    items: DduItem[];
  }): Promise<DduItem[]> {
    const input = args.input;
    const filtered = args.items.filter((i) => hasMatch(input, i.word));
    if (filtered.length > 100000) {
      return Promise.resolve(filtered);
    }
    return Promise.resolve(
      filtered.map((
        c,
      ) => ({ score: score(input, c.word), item: c } as SortItem))
        .sort((a, b) => b.score - a.score).map((c) => c.item),
    );
  }

  params(): Params {
    return {};
  }
}
