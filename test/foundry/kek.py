f = open("output.txt", "r")
a = f.readlines()

alls = []

for i in range(len(a)):
    if (a[i][:5] == "Logs:"):
        try:
            alls.append(int(a[i+1]))
        except:
            pass
alls = sorted(alls)
print(alls)
print(len(alls))