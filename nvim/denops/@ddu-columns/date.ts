import {
  BaseColumn,
  DduItem,
  ItemHighlight,
} from "https://deno.land/x/ddu_vim@v2.1.0/types.ts";
import { GetTextResult } from "https://deno.land/x/ddu_vim@v2.1.0/base/column.ts";
import { Denops } from "https://deno.land/x/ddu_vim@v2.1.0/deps.ts";
import { format } from "https://deno.land/std@0.178.0/datetime/format.ts";

type Params = {
  format: string;
};

export class Column extends BaseColumn<Params> {
  override async getLength(args: {
    denops: Denops;
    columnParams: Params;
    items: DduItem[];
  }): Promise<number> {
    const widths = await Promise.all(args.items.map(
      (item) => {
        const time = item.status?.time;
        return time
          ? format(new Date(time), args.columnParams.format).length
          : 0;
      },
    )) as number[];
    return Math.max(...widths);
  }

  override getText(args: {
    columnParams: Params;
    startCol: number;
    endCol: number;
    item: DduItem;
  }): Promise<GetTextResult> {
    const time = args.item.status?.time;
    return Promise.resolve({
      text: args.item.display +
        (time ? format(new Date(time), args.columnParams.format) : ""),
    });
  }

  override params(): Params {
    return {
      format: "yy-MM-dd HH:mm",
    };
  }
}
