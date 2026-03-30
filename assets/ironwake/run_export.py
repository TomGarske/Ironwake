"""
run_export.py - Enables BlenderKit, manually starts its client service,
                then runs blender_export_to_glb.py in headless mode.
"""
import bpy
import os
import time

# ---------------------------------------------------------------------------
# 1. Enable BlenderKit addon
# ---------------------------------------------------------------------------
addon_name = "blenderkit"
if addon_name not in bpy.context.preferences.addons:
    print(f"[run_export] Enabling addon: {addon_name}")
    bpy.ops.preferences.addon_enable(module=addon_name)
    bpy.ops.wm.save_userpref()
else:
    print(f"[run_export] BlenderKit already enabled.")

# ---------------------------------------------------------------------------
# 2. Manually start the BlenderKit client service
#    (skipped by timer system in --background mode)
# ---------------------------------------------------------------------------
try:
    from blenderkit import client_lib, global_vars

    print(f"[run_export] Starting BlenderKit client service...")
    client_lib.start_blenderkit_client()
    time.sleep(3)  # Give the client a moment to bind its port

    for attempt in range(10):
        try:
            client_lib.get_reports(os.getpid())
            print(f"[run_export] BlenderKit client is up on port {global_vars.CLIENT_PORTS[0]}")
            break
        except Exception as e:
            print(f"[run_export] Waiting for client... ({attempt+1}/10)")
            time.sleep(1)
    else:
        print("[run_export] WARNING: BlenderKit client did not respond — downloads will fail.")

except Exception as e:
    print(f"[run_export] Could not start BlenderKit client: {e}")

# ---------------------------------------------------------------------------
# 3. Inject a task-pump helper into builtins for the download polling loop
# ---------------------------------------------------------------------------
def _bk_pump(app_id):
    """Poll the BlenderKit client and process any completed download tasks."""
    try:
        from blenderkit import client_lib, client_tasks
        from blenderkit import timer as bk_timer
        results = client_lib.get_reports(app_id)
        for td in results:
            task = client_tasks.Task(
                data=td.get("data", {}),
                task_id=td.get("task_id", ""),
                app_id=td.get("app_id", 0),
                task_type=td.get("task_type", ""),
                message=td.get("message", ""),
                message_detailed=td.get("message_detailed", ""),
                progress=td.get("progress", 0),
                status=td.get("status", ""),
                result=td.get("result", {}),
            )
            bk_timer.handle_task(task)
    except Exception:
        pass

import builtins
builtins._bk_pump = _bk_pump
builtins._bk_app_id = os.getpid()

# ---------------------------------------------------------------------------
# 4. Run the main export script
# ---------------------------------------------------------------------------
script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "blender_export_to_glb.py")
print(f"[run_export] Running: {script_path}")
exec(open(script_path).read())
