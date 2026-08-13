Output assets/demo.mp4

Require nvim

Set Shell "bash"
Set FontFamily "FiraCode Nerd Font"
Set FontSize 18
Set Width 1280
Set Height 720
Set Theme "Catppuccin Mocha"
Set Padding 16
Set Margin 24
Set MarginFill "#1c1c1c"
Set BorderRadius 12
Set WindowBar Colorful
Set WindowBarSize 48
Set Framerate 60
Set TypingSpeed 60ms
Set CursorBlink false

Hide
Type@0ms "cd scripts/demo/fixtures && alias nvim='nvim -u ../init.lua' && clear"
Enter
Show
Type "nvim -d a.go b.go"
Enter
Hide
Sleep 2s
Show
Sleep 1500ms

# Comment on the unbounded retry in b.go.
Escape
Type ":wincmd l"
Enter
Sleep 300ms
Type ":4"
Enter
Sleep 400ms
Type ":Margin comment"
Enter
Sleep 500ms
Type@35ms "Bound retries and add backoff."
Sleep 300ms
Ctrl+S
Sleep 1100ms

# Comment on the removed retry bound in a.go.
Escape
Type ":wincmd h"
Enter
Sleep 300ms
Type ":4"
Enter
Sleep 400ms
Type ":Margin comment"
Enter
Sleep 500ms
Type@35ms "Keep the three-attempt limit."
Sleep 300ms
Ctrl+S
Sleep 1100ms

# Comment on c.go outside the diff.
Escape
Type ":e c.go"
Sleep 300ms
Enter
Type ":only"
Enter
Sleep 700ms
Type ":19"
Enter
Sleep 400ms
Type ":Margin comment"
Enter
Sleep 500ms
Type@35ms "Wait on a timer or ctx.Done() so cancellation stops retries."
Sleep 300ms
Ctrl+S
Sleep 1100ms

# Edit, inspect, and copy the exported comment.
Escape
Type ":Margin export"
Enter
Sleep 1200ms
Type "gg0C"
Type@35ms "Please fix the following:"
Escape
Type "0jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"
Sleep 500ms
Type@500ms "ggVGy"
Sleep 500ms
Type ":close"
Enter
Sleep 1500ms
Type "y:qa"
Enter
