#!/usr/bin/env python3
"""Look for a vertical wrap ("seam") in frames from the capture card.

After a capture restart the driver can come up out of phase: every frame is
wrapped vertically, the bottom part of the picture on top and the top part
below a seam. This measures the strongest horizontal edge per frame with the
same statistic as the driver's sc0710_detect_horizontal_tear() (mean |dY|
between adjacent rows, sampled every width/128 pixels, flagged when >= 42 and
> 2 x average + 12) and saves the frame for a look by eye. The statistic cannot
tell a seam from a real full-width line in the picture (the Switch HOME menu
has one at row 970), so always look at the saved frame.

  frame-seam.py                 grab one frame from the card now
  frame-seam.py FILE...         measure saved images
  frame-seam.py --watch [SECS]  grab a frame 5 s after every capture restart
                                (kernel log "DMA restarted"), default 1200 s

Frames go to out/seam/ in the repo. Grabbing works while the player runs
(a second capture client does not disturb it). Needs ffmpeg.
"""
import glob, os, subprocess, sys, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "seam")
W, H = 1920, 1080


def find_node():
    for dev in sorted(glob.glob("/sys/class/video4linux/video*")):
        try:
            vendor = open(os.path.join(dev, "device", "vendor")).read().strip()
            device = open(os.path.join(dev, "device", "device")).read().strip()
        except OSError:
            continue
        if (vendor, device) == ("0x12ab", "0x0710"):
            return "/dev/" + os.path.basename(dev)
    sys.exit("frame-seam: no sc0710 video node (is the module loaded?)")


def grab(label):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, time.strftime("%Y%m%d-%H%M%S") + "-" + label + ".png")
    # Skip the first frames: the driver drops/validates them after a restart.
    subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "v4l2",
                    "-input_format", "yuyv422", "-i", find_node(),
                    "-vf", "select='gte(n,10)'", "-frames:v", "1", "-y", path],
                   timeout=15, check=True)
    return path


def measure(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf",
                          f"scale={W}:{H}", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                         capture_output=True, check=True).stdout
    step = max(8, W // 128)
    scores = []
    for y in range(H - 1):
        r0, r1 = raw[y * W:(y + 1) * W], raw[(y + 1) * W:(y + 2) * W]
        s = [abs(r1[x] - r0[x]) for x in range(0, W, step)]
        scores.append(sum(s) // len(s))
    mx = max(scores)
    avg = sum(scores) // len(scores)
    flag = mx >= 42 and mx > avg * 2 + 12
    luma = sum(raw) // len(raw)
    return (f"{os.path.basename(path)}: strongest edge at row {scores.index(mx) + 1}, "
            f"score {mx} (average {avg}), driver would flag: {'YES' if flag else 'no'}, "
            f"mean luma {luma}")


def watch(seconds):
    print(f"watching the kernel log for {seconds} s; wake or re-plug the source to test")
    log = subprocess.Popen(["journalctl", "-k", "-f", "-n", "0", "--no-pager", "-o", "cat"],
                           stdout=subprocess.PIPE, text=True)
    end, n = time.time() + seconds, 0
    try:
        for line in log.stdout:
            if time.time() > end:
                break
            if "Tear seam persisted" in line:
                print(time.strftime("%T"), "driver:", line.strip())
            elif "DMA restarted" in line:
                n += 1
                time.sleep(5)
                print(time.strftime("%T"), f"restart {n}:", measure(grab(f"restart{n}")), flush=True)
    finally:
        log.terminate()


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--watch"]:
        watch(int(args[1]) if len(args) > 1 else 1200)
    elif args:
        for f in args:
            print(measure(f))
    else:
        print(measure(grab("now")))
