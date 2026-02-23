# User Guide — Flood Results Dashboard

## Purpose

This guide explains how to open and use the flood visualization dashboard.

This document is intended for:
- Decision makers
- Disaster management teams
- Stakeholders
- Non-technical users

If you need to run simulations → See RUNNING.md  
If you need to install system → See INSTALL.md  

Note: The dashboard is only available on desktop Linux systems. It cannot be run on HPC clusters (no display, no browser). If simulations were run on HPC, outputs must be transferred to a desktop system first.

---

## 1. Accessing The Dashboard

If your IT / HPC team has already started the system on a desktop Linux machine:

Open browser and go to:
`http://localhost:5173`

If you do not know the dashboard URL, contact your system operator.

If simulations were run on an HPC cluster, the operator must first transfer the output files to the desktop system before the dashboard will show any data.

---

## 2. If Dashboard Is Not Running (Operator Section)

If you are responsible for starting services:

Note: All steps below apply to desktop Linux only. If simulations were run on HPC, copy output files from the cluster to this machine first:
```bash
scp user@hpc-cluster:/path/to/anuga_outputs/*.sww ./mahanadi_test_case/anuga_outputs/
```
Then run bridge.py manually to deploy to GeoServer before starting the dashboard.

---

### Step 1 — Start Map Server (GeoServer)

```bash
make geoserver-start
```
OR
```bash
bash build/geoserver_start.sh
```

Verify server:
```bash
curl -I http://localhost:8080/geoserver
```

Expected: 200 or 302 status.

---

### Step 2 — Start Dashboard (React App)
```bash
source build/setup_tools_env.sh
cd anuga-viewer-app
npm run dev
```

Dashboard default URL:
`http://localhost:5173`


---

## 3. Using The Dashboard

---

### Layer Selection (Right Panel)

#### Max Depth Layer
Shows maximum water depth reached during simulation.

Use this for:
- Worst-case flood extent
- Risk assessment
- Planning evacuation zones

---

#### Time Series Layer
Shows flood evolution over time.

Use this for:
- Flood arrival time
- Flood progression analysis
- Emergency response timing

---

## 4. Time Slider

When Time Series layer is selected:

You will see a time slider.

You can:
- Drag to move through simulation time
- See flood growth or recession

Each step represents a simulation time interval.

---

## 5. Map Navigation

Zoom:
Mouse wheel OR +/- buttons

Pan:
Click and drag

Auto Center:
Map automatically moves to selected dataset area.

---

## 6. Understanding Flood Colors

| Color | Depth | Meaning |
|---|---|---|
| Yellow | 0.01 – 0.2 m | Minor water accumulation |
| Orange | 0.5 – 1.0 m | Vehicle movement risky |
| Red | 2.0 – 3.5 m | Dangerous for people |
| Dark Red | 5.0 – 10 m+ | Severe flooding, structural risk |

No Color = Dry Area

---

## 7. Common Questions

---

### Map Is Blank
Check:
- Layer selected?
- Wait few seconds for loading
- Internet / network connectivity
- Contact operator if issue persists

---

### Time Slider Not Working
Make sure:
Time Series layer selected (not Max Depth)

---

### Data Not Visible
Possible causes:
- Simulation not deployed to GeoServer
- GeoServer not running
- Network access blocked

---

## 8. Good Practices

For best performance:
- Use Chrome or Edge browser
- Stable internet connection
- Avoid opening too many layers simultaneously

---

## 9. When To Contact Support

Contact support if:
- Dashboard not opening
- Layers not loading after long wait
- Data appears corrupted or missing
- Access denied errors

---

## Support Contact

Anup Bagde  
Project Engineer - HPC ESEG Group  
CDAC Pune  
Email: anupb@cdac.in

---