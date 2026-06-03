important task
We need a gui way to update the yaml config automatically to make the rules easier.
  rules you can click through like hazel, we should keep parity with features but legally different, by being better.
here is sort of how hazel does it: you click new rule, it opens a madlib it says *if*, then selectable options, then *in*, selectable options based on common locations and home folders and browse, *has or hasnt the following quality" then selectable options, *do* exec selectable options or run scripts etc, heres an actual example below

In Folders Downloads Rule Name: Old Items


If
  *all* or *any* *none*

❯ Name
  Extension
  Full Name
  V Date Added
  Date Created
  Date Last Modified
  Date Last Opened
  Date Last Matched
  Current Time
  Kind
  Tags
  Color Label
  Comment
  Size                  t
  Locked
  Contents
  Source URL/Address
  Subfolder Depth
  Sub-file/folder Count
  Any File
  Passes AppleScript
  Passes JavaScript
  Passes shell script
  Other...

Has the following quality:
❯ is not is before
  is after
  is in the last
  is not in the last
  is in the next
  is not in the next
  occurs at
  occurs before
  occurs after
  is among the is not among the
  did change did not change is blank
  is not blank

Time field
0-*

Minutes
Hours
Days
Weeks
Months
Years
Then exec
 Move
    Copy
  ❯ Move

  Sort into subfolder

  Sync

  Upload

  Add tags

  Remove tags

  / Set color label

  Add comment

  Toggle extension

  Toggle lock

  Archive

  Unarchive

  Open

  Show in Finder

  Make alias

  Import into Music

  Import into Photos

  Import into TV

  Run Shortcut

  Run AppleScript

  Run JavaScript

  Run Automator workflow

  Run shell script
  no
  Pause
  Run rules on folder contents
  Continue matching rules
  Display notification
  Ignore

These are the exact options in the gui for editing from hazel. We need options similar to these with the same features. An example if all date added is not in the last 4 weeks sort into sub folder
Be creative when necessary to make this convenient. Add features here:
With the Pattern (use a better term if you can)
  Name, extension, domain, source folder, other
Kind, comment, date added, current date, date modified, date created, date opened, > …
Or other things like that as an example.
IgnoreIgnore  Display notification

Ignore
