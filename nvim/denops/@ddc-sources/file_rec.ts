import { Item } from "jsr:@shougo/ddc-vim@7.0.0/types";
import { BaseSource } from "jsr:@shougo/ddc-vim@7.0.0/source";
import { vimoption2ts } from "jsr:@shougo/ddc-vim@7.0.0/utils";
import {
  GatherArguments,
  GetCompletePositionArguments,
} from "jsr:@shougo/ddc-vim@7.0.0/source";
import * as fn from "jsr:@denops/std@7.1.1/function";
import * as op from "jsr:@denops/std@7.1.1/option";
import { relative, resolve } from "jsr:@std/path@1.0.3";

type Params = {
  cmd: string[];
  path: string;
};

async function getOutput(cwd: string, cmds: string[]): Promise<string[]> {
  try {
    const proc = Deno.run({
      cmd: cmds,
      stdout: "piped",
      stderr: "piped",
      cwd: cwd,
    });
    const [status, stdout, stderr] = await Promise.all([
      proc.status(),
      proc.output(),
      proc.stderrOutput(),
    ]);
    proc.close();

    if (!status.success) {
      console.error(new TextDecoder().decode(stderr));
      return [];
    }
    return (new TextDecoder().decode(stdout)).split("\n");
  } catch (e: unknown) {
    console.error(e);
    return [];
  }
}

export class Source extends BaseSource<Params> {
  async getCompletePosition({
    context,
    denops,
  }: GetCompletePositionArguments<Params>): Promise<number> {
    const fnamePattern = `[${
      vimoption2ts(await op.isfname.getGlobal(denops))
    }]*`;
    console.log(fnamePattern);
    const matchPos = context.input.search(
      new RegExp("(?:" + fnamePattern + ")$"),
    );
    console.log(matchPos);
    const completePos = matchPos ?? -1;
    return Promise.resolve(completePos);
  }

  async gather({
    denops,
    sourceParams,
  }: GatherArguments<Params>): Promise<Item[]> {
    let dir = await fn.expand(denops, sourceParams.path) as string;
    if (dir == "") {
      dir = await fn.getcwd(denops) as string;
    }

    console.log(dir);
    if (!sourceParams.cmd.length) {
      return [];
    }
    const paths = await getOutput(dir, sourceParams.cmd);
    const items: Item[] = [];
    paths.map((path) => {
      if (!path.length) return;
      const fullPath = resolve(dir, path);
      items.push({
        word: relative(dir, fullPath),
      });
    });
    return items;
  }

  params(): Params {
    return {
      cmd: [],
      path: "",
    };
  }
}
