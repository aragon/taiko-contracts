// Run this program with:
// $ cat file | deno run test/script/make-test-tree.ts

type Line = { content: string; indentation: number };
type TreeItem = { content: string; children: Array<TreeItem> };

async function main() {
  const content = await readStdinText();
  Deno.stdout.write(new TextEncoder().encode(transformContent(content)));
}

function transformContent(content: string) {
  const lines = parseLines(content);
  if (!lines.length) return;

  const root: TreeItem = {
    content: lines[0].content,
    children: parseChildrenLines(lines.slice(1)),
  };
  return formatTree(root);
}

function parseLines(input: string): Array<Line> {
  const lines = input
    .split("\n")
    .map((line) => {
      const match = line.match(/^\s*(#*)\s*(.*)/);
      if (!match || !match[2].trim()) return null;

      let result: Line = {
        indentation: match[1].length,
        content: match[2].trim(),
      };
      return result;
    })
    .filter((line) => !!line);

  if (!lines.length) return [];

  // Sanity checks
  let count = lines.filter((line) => line.indentation === 0).length;
  if (count > 1) {
    throw new Error("There can be only one root element at the begining");
  } else if (lines[0].indentation != 0) {
    throw new Error("The first element should have no indentation");
  }

  for (let i = 1; i < lines.length; i++) {
    if (lines[i].indentation > lines[i - 1].indentation + 1) {
      throw new Error(
        "Incorrect indentation: Was " +
          lines[i - 1].indentation +
          " and now is " +
          lines[i].indentation
      );
    }
  }

  return lines;
}

function parseChildrenLines(
  lines: Array<Line>,
  parentIndentation = 0
): Array<TreeItem> {
  if (!lines.length) return [];

  const result: Array<TreeItem> = [];

  for (let i = 0; i < lines.length; i++) {
    const item = lines[i];
    // Iterate over the direct children
    if (item.indentation != parentIndentation + 1) continue;

    // Determine the boundaries of `item`'s children
    let j = i + 1;
    for (; j < lines.length; j++) {
      if (lines[j].indentation <= item.indentation) break;
    }

    // Process our subsegment only
    const children = lines.slice(i, j);
    result.push({
      content: item.content,
      children: parseChildrenLines(children, item.indentation),
    });
  }

  return result;
}

function formatTree(root: TreeItem): string {
  let result = root.content + "\n";

  for (let i = 0; i < root.children.length; i++) {
    const item = root.children[i];
    const newLines = formatTreeItem(item, i === root.children.length - 1);
    result += newLines.join("\n") + "\n";
  }

  return result;
}

function formatTreeItem(
  root: TreeItem,
  lastChildren: boolean,
  prefix = ""
): Array<string> {
  const result: string[] = [];

  // Add ourselves
  if (lastChildren) {
    result.push(prefix + "└── " + root.content);
  } else {
    result.push(prefix + "├── " + root.content);
  }

  // Add any children
  for (let i = 0; i < root.children.length; i++) {
    const item = root.children[i];

    // Last child
    if (i === root.children.length - 1) {
      const newPrefix = lastChildren ? prefix + "    " : prefix + "│   ";
      const lines = formatTreeItem(item, true, newPrefix);
      lines.forEach((line) => result.push(line));
      continue;
    }

    // The rest of children
    const newPrefix = lastChildren ? prefix + "    " : prefix + "│   ";
    const lines = formatTreeItem(item, false, newPrefix);
    lines.forEach((line) => result.push(line));
  }

  return result;
}

async function readStdinText() {
  let result = "";
  const decoder = new TextDecoder();
  for await (const chunk of Deno.stdin.readable) {
    const text = decoder.decode(chunk);
    result += text;
  }
  return result;
}

if (import.meta.main) {
  main().catch((err) => {
    console.error("Error: " + err.message);
  });
}
