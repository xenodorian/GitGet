GitGet Diagnostic (read-only)

WHAT THIS IS
A small program that reads information about your handheld and saves it to
one text file. The file is used to decide what the GitGet app needs in order
to run on your device. It does not install anything, change any setting,
open the internet, or record Wi-Fi names, keys, MAC addresses, or serial
numbers.

INSTALL (no commands needed)
1. Shut down the handheld and take out the microSD card that holds your
   games (the one with folders such as "ports" and "gba").
2. Put the card in your PC and open the drive that has a folder named
   "ports".
3. Extract this ZIP into the root of that drive. Afterwards the file
   "GitGet Diagnostic.sh" must be inside the "ports" folder, with a folder
   named "gitget-diag" next to it. If asked to merge folders, say yes.
   If your games are on the second card, use that card instead.
4. Eject the card, put it back, and start the handheld.

RUN
1. In EmulationStation open Ports, then "GitGet Diagnostic".
   If it is not listed: press Start, choose Quit, then Restart
   EmulationStation (or reboot the handheld).
2. Wait. The screen shows a progress message, then DONE with the report
   location. It closes by itself after 20 seconds. No button presses are
   needed.
3. Shut down the handheld from the menu. Do not just pull the power.
4. Put the card in the PC. Open ports\gitget-diag and find the file
   GitGet_Device_Report.txt. Upload that file to the chat.

IF THE REPORT IS NOT THERE
The tool tries these places in order and shows the one it used on screen:
ports\gitget-diag, the ports folder, the card root, then /tmp (which is not
kept after shutdown).

SAFETY
The tool only reads system information. The only file it creates is the
report (plus a short-lived temporary file in the same folder that it removes
itself). To remove the tool, delete "GitGet Diagnostic.sh" and the
"gitget-diag" folder from the ports folder.

FILES IN THIS PACKAGE
MANIFEST.txt lists every file with its SHA-256 checksum.
