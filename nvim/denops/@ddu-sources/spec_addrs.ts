import {
  BaseSource,
  Context,
  Item,
  SourceOptions,
} from "https://deno.land/x/ddu_vim@v3.10.3/types.ts";
import { Denops } from "https://deno.land/x/ddu_vim@v3.10.3/deps.ts";
import { ActionData } from "../@ddu-kinds/spec_history.ts";
import { basename } from "https://deno.land/std@0.220.1/path/mod.ts";

type Params = {
  histFile: string;
  binPath: string;
  histlen: number;
  shorten: boolean;
  targetAddr: number;
  minN: number;
};

type GatherArgs = {
  denops: Denops;
  context: Context;
  sourceOptions: SourceOptions;
  sourceParams: Params;
};

export type CSVItem = {
  histlen: number;
  pattern: number[];
  n_taken: number;
  n_untaken: number;
  countSame?: number;
};

function addr2line(
  addrs: number[],
  binPath: string,
  opts?: string[],
): string[] {
  const command = new Deno.Command("addr2line", {
    args: [
      "-e",
      binPath,
      ...addrs.map((addr) => "0x" + addr.toString(16)),
    ],
  });
  const { code, stdout, stderr } = command.outputSync();
  if (code !== 0) {
    console.error(new TextDecoder().decode(stderr));
    return [];
  }
  return new TextDecoder().decode(stdout).trim().split("\n");
}

function gunzip(path: string): string {
  const command = new Deno.Command("gunzip", {
    args: [
      "-c",
      path,
    ],
  });
  const { code, stdout, stderr } = command.outputSync();
  if (code !== 0) {
    console.error(new TextDecoder().decode(stderr));
    return "";
  }
  return new TextDecoder().decode(stdout);
}

function get_addr_to_place_index_map(
  addrs: number[],
  binPath: string,
): Map<number, number> {
  const places = addr2line(addrs, binPath).map((line) => {
    const [file, lineNr] = line.split(":");
    return `${basename(file)}:${lineNr}`;
  });
  const addr_place_map = new Map<number, string>();
  addrs.forEach((addr, i) => addr_place_map.set(addr, places[i]));
  const place_index_map = new Map<string, number>();
  Array.from(new Set(places)).forEach((place, i) =>
    place_index_map.set(place, i)
  );
  const addr_to_place_index_map = new Map<number, number>();
  addrs.forEach((addr) => {
    const place = addr_place_map.get(addr);
    if (place === undefined) {
      throw new Error(`place not found for addr: ${addr}`);
    }
    const index = place_index_map.get(place);
    if (index === undefined) {
      throw new Error(`index not found for place: ${place}`);
    }
    addr_to_place_index_map.set(addr, index);
  });
  return addr_to_place_index_map;
}

function gather_positions(
  args: GatherArgs,
): ReadableStream<Item<ActionData>[]> {
  const addrs = (args.sourceOptions.path as string).split(" ");
  const command = new Deno.Command("addr2line", {
    args: ["-fC", "-e", args.sourceParams.binPath, ...addrs],
  });
  const { code, stdout, stderr } = command.outputSync();
  if (code !== 0) {
    console.error(new TextDecoder().decode(stderr));
    return new ReadableStream({
      start(controller) {
        controller.close();
      },
    });
  }
  const lines = new TextDecoder().decode(stdout).trim().split("\n");
  const items: Item<ActionData>[] = [];
  for (let i = 0; i < lines.length / 2; i++) {
    const func = lines[i * 2];
    const [path, lineNr] = lines[i * 2 + 1].split(":");
    items.push({
      word: `${func} at ${basename(path)}:${lineNr}`,
      action: {
        path,
        lineNr: Number(lineNr.split(" ")[0]),
      },
    });
  }
  return new ReadableStream({
    start(controller) {
      controller.enqueue(items);
      controller.close();
    },
  });
}

function gather_path_histories(
  args: GatherArgs,
): ReadableStream<Item<ActionData>[]> {
  const lines = gunzip(args.sourceParams.histFile).trim().split(
    "\n",
  );
  let items: CSVItem[] = [];
  for (const line of lines.slice(1)) {
    const [h, pattern, nT, nUt] = line.split(",");
    const histlen = parseInt(h);
    const nTaken = parseInt(nT);
    const nUntaken = parseInt(nUt);
    if (histlen === args.sourceParams.histlen) {
      const addrs = pattern.trim().split(" ").map((c) => parseInt(c));
      items.push({
        histlen: histlen,
        pattern: addrs,
        n_taken: nTaken,
        n_untaken: nUntaken,
        countSame: 1,
      });
    }
  }
  const addr_set = new Set<number>();
  items.forEach((item) => item.pattern.forEach((addr) => addr_set.add(addr)));
  const addr_index_map = new Map<number, number>();
  for (const addr of [...addr_set].sort()) {
    addr_index_map.set(addr, addr_index_map.size);
  }

  if (args.sourceParams.shorten) {
    const addrs = Array.from(addr_set);
    const addr_to_place_index_map = get_addr_to_place_index_map(
      addrs,
      args.sourceParams.binPath,
    );
    const new_items: Map<string, CSVItem> = new Map();
    for (const item of items) {
      const new_pattern = item.pattern.map((addr) =>
        addr_to_place_index_map.get(addr)
      );
      const key = new_pattern.join(" ");
      if (!new_items.has(key)) {
        new_items.set(key, item);
      } else {
        const old_item = new_items.get(key);
        if (old_item === undefined) {
          throw new Error(`item not found for key: ${key}`);
        }
        old_item.n_taken += item.n_taken;
        old_item.n_untaken += item.n_untaken;
        old_item.countSame! += 1;
      }
    }
    items = Array.from(new_items.values());
  }

  const dduItems: Item<ActionData>[] = items.filter(
    (item) => item.n_taken + item.n_untaken >= args.sourceParams.minN,
  ).map((item) => {
    return {
      word: `${
        item.pattern.map((addr) => addr_index_map.get(addr)).join("\t")
      }\tT:${item.n_taken}\tUT:${item.n_untaken}\t(${item.countSame})`,
      isTree: true,
      treePath: item.pattern.map((addr) => addr.toString(16)).join(" "),
      action: {
        binPath: args.sourceParams.binPath,
      },
    };
  });
  const targetLine =
    addr2line([args.sourceParams.targetAddr], args.sourceParams.binPath)[0];
  const [file, lineNr] = targetLine.split(":");
  dduItems.splice(0, 0, {
    word: `${basename(file)}:${lineNr}`,
    isTree: false,
    action: {
      path: file,
      lineNr: Number(lineNr),
    },
  });

  return new ReadableStream({
    start(controller) {
      controller.enqueue(dduItems);
      controller.close();
    },
  });
}

export class Source extends BaseSource<Params> {
  override kind = "spec_history";

  // override onInit(args: {
  //   denops: Denops;
  //   sourceOptions: SourceOptions;
  //   sourceParams: Params;
  // }): void {}

  override gather(args: GatherArgs): ReadableStream<Item<ActionData>[]> {
    if (args.sourceOptions.path === "") {
      return gather_path_histories(args);
    } else {
      return gather_positions(args);
    }
  }

  override params(): Params {
    return {
      histFile: "",
      binPath: "",
      histlen: 0,
      shorten: false,
      targetAddr: 0,
      minN: 0,
    };
  }
}
