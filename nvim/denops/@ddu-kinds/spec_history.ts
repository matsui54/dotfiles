import {
  DduItem,
  PreviewContext,
  Previewer,
} from "https://deno.land/x/ddu_vim@v3.10.3/types.ts";
import { Kind as FileKind } from "https://deno.land/x/ddu_kind_file@v0.7.1/file.ts";
import { Denops } from "https://deno.land/x/ddu_vim@v3.10.3/deps.ts";
import { ActionData as FileActionData } from "https://deno.land/x/ddu_kind_file@v0.7.1/file.ts";
import { basename } from "https://deno.land/std@0.220.1/path/mod.ts";

export type ActionData = {
  binPath?: string;
} & FileActionData;

export class Kind extends FileKind {
  override getPreviewer(args: {
    denops: Denops;
    item: DduItem;
    actionParams: unknown;
    previewContext: PreviewContext;
  }): Promise<Previewer | undefined> {
    if (args.item.isTree) {
      const addrs = (args.item.treePath as string).split(" ");
      const command = new Deno.Command("addr2line", {
        args: ["-e", (args.item.action as ActionData).binPath ?? "", ...addrs],
      });
      const { code, stdout, stderr } = command.outputSync();
      if (code !== 0) {
        console.error(new TextDecoder().decode(stderr));
      }
      const contents = new TextDecoder().decode(stdout).trim().split("\n").map(
        (line) => {
          const [path, lineNr] = line.split(" ")[0].split(":");
          return `${basename(path)}:${lineNr}`;
        },
      );
      return Promise.resolve({
        kind: "nofile",
        contents,
      });
    } else {
      return super.getPreviewer(args);
    }
  }
}
