import subprocess
from pathlib import Path


def confirm() -> bool:
    choice = input("OK to `git commit and push`? [y/N]: ").lower()
    if choice in ["y", "ye", "yes"]:
        return True
    return False


for p in Path(".").glob("dd*-*/Makefile"):
# git remote set-url origin git@github.com:matsui54/ddc-matcher_fuzzy.git
    print(p.parent)
    diff = subprocess.run(
        ["git", "diff", "--name-only"], stdout=subprocess.PIPE, cwd=p.parent
    ).stdout.strip()
    if not diff:
        continue
    subprocess.run(["make", "type-check"], cwd=p.parent).check_returncode()
    subprocess.run(["git", "diff"], cwd=p.parent)
    if confirm():
        subprocess.run(["git", "remote", "set-url", "origin", f"git@github.com:matsui54/{p.parent}.git"], cwd=p.parent).check_returncode()
        subprocess.run(["git", "add", "."], cwd=p.parent).check_returncode()
        subprocess.run(
            ["git", "commit", "-m", "📦 Update Deno dependencies"], cwd=p.parent
        ).check_returncode()
        subprocess.run(["git", "push"], cwd=p.parent).check_returncode()
    else:
        print("canceled")
