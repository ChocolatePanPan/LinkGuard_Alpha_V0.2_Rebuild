"""
resource_server.py — LinkGuard 資源管理伺服器
Port 8006, FastAPI
管理救援資源（救護車、醫療包、人員）的即時狀態
"""

from __future__ import annotations

import asyncio
import json
import socket
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import linkguard_db
from utils import now_iso, send_to_tcp_with_retry, health_check_response
from i18n import t

TZ_TW = timezone(timedelta(hours=8))
TCP_SERVER_HOST = "127.0.0.1"
TCP_SERVER_PORT = 9000

app = FastAPI(title="LinkGuard Resource Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def _send_to_tcp(msg: dict):
    await asyncio.to_thread(send_to_tcp_with_retry, msg, "RESOURCE")


async def _broadcast_resource_update():
    """廣播完整資源列表 + 摘要"""
    resources = linkguard_db.get_all_resources()
    summary = linkguard_db.get_resource_summary()
    await _send_to_tcp({
        "type": "resource_update",
        "device_id": "resource-server",
        "timestamp": now_iso(),
        "data": {
            "resources": resources,
            "summary": summary,
        },
    })


# === 資料模型 ===

class CreateResource(BaseModel):
    resource_id: str
    type: str  # ambulance, medical_kit, personnel
    name: str
    total: int = 1
    location_desc: str = ""
    assigned_zone: str = ""


class UpdateResource(BaseModel):
    available: Optional[int] = None
    status: Optional[str] = None
    assigned_to: Optional[str] = None
    assigned_zone: Optional[str] = None
    location_desc: Optional[str] = None


class DeployResource(BaseModel):
    assigned_to: str
    assigned_zone: str = ""
    location_desc: str = ""
    quantity: int = 1


class ReturnZoneResource(BaseModel):
    assigned_zone: str
    quantity: int = 1


def _primary_assignment(resource_id: str) -> tuple[str, str]:
    allocations = linkguard_db.get_resource_allocations(resource_id)
    if not allocations:
        return "", ""
    first = allocations[0]
    return first.get("assigned_to", "") or "", first.get("assigned_zone", "") or ""


# === 路由 ===

@app.on_event("startup")
async def startup():
    linkguard_db.init_db()
    print("[RESOURCE] Resource server 已啟動")


@app.get("/resources")
async def list_resources():
    resources = linkguard_db.get_all_resources()
    summary = linkguard_db.get_resource_summary()
    return {"resources": resources, "summary": summary}


@app.post("/resources")
async def create_resource(req: CreateResource):
    linkguard_db.save_resource({
        "resource_id": req.resource_id,
        "type": req.type,
        "name": req.name,
        "total": req.total,
        "available": req.total,
        "location_desc": req.location_desc,
        "assigned_zone": req.assigned_zone,
        "status": "available",
    })
    linkguard_db.log_event(
        "resource_create", "resource-server",
        f"新增資源: {req.resource_id} ({req.name})", "info",
    )
    await _broadcast_resource_update()
    return {"status": "ok", "resource_id": req.resource_id}


@app.patch("/resources/{resource_id}")
async def update_resource(resource_id: str, req: UpdateResource):
    existing = linkguard_db.get_resource(resource_id)
    if not existing:
        raise HTTPException(status_code=404, detail=t("err.resource_not_found"))

    updates = {}
    if req.available is not None:
        updates["available"] = req.available
    if req.status is not None:
        updates["status"] = req.status
    if req.assigned_to is not None:
        updates["assigned_to"] = req.assigned_to
    if req.assigned_zone is not None:
        updates["assigned_zone"] = req.assigned_zone
    if req.location_desc is not None:
        updates["location_desc"] = req.location_desc

    if updates:
        linkguard_db.update_resource(resource_id, updates)
        await _broadcast_resource_update()

    return {"status": "ok", "resource_id": resource_id}


@app.post("/resources/{resource_id}/deploy")
async def deploy_resource(resource_id: str, req: DeployResource):
    existing = linkguard_db.get_resource(resource_id)
    if not existing:
        raise HTTPException(status_code=404, detail=t("err.resource_not_found"))

    available = existing["available"]
    quantity = max(1, req.quantity)
    if available < quantity:
        raise HTTPException(status_code=400, detail=t("err.no_available_resource"))

    assigned_zone = (req.assigned_zone or req.assigned_to).strip()
    new_available = available - quantity

    linkguard_db.update_resource(resource_id, {
        "available": new_available,
        "status": "in_use",
        "assigned_to": req.assigned_to,
        "assigned_zone": assigned_zone,
        "location_desc": req.location_desc or existing["location_desc"],
    })
    linkguard_db.upsert_resource_allocation(
        resource_id,
        assigned_zone=assigned_zone,
        quantity=quantity,
        location_desc=req.location_desc or existing["location_desc"],
        assigned_to=req.assigned_to,
    )
    linkguard_db.log_event(
        "resource_deploy", "resource-server",
        f"部署資源: {resource_id} x{quantity} → {assigned_zone}", "info",
    )
    await _broadcast_resource_update()
    return {"status": "ok", "resource_id": resource_id, "available": new_available}


@app.post("/resources/{resource_id}/return")
async def return_resource(resource_id: str):
    existing = linkguard_db.get_resource(resource_id)
    if not existing:
        raise HTTPException(status_code=404, detail=t("err.resource_not_found"))

    returned = linkguard_db.return_resource_allocation(resource_id, quantity=1)
    new_available = min(existing["available"] + max(returned, 1), existing["total"])
    status = "available" if new_available == existing["total"] else "in_use"
    assigned_to, assigned_zone = _primary_assignment(resource_id)

    linkguard_db.update_resource(resource_id, {
        "available": new_available,
        "status": status,
        "assigned_to": "" if status == "available" else assigned_to,
        "assigned_zone": "" if status == "available" else assigned_zone,
    })
    linkguard_db.log_event(
        "resource_return", "resource-server",
        f"資源回收: {resource_id}", "info",
    )
    await _broadcast_resource_update()
    return {"status": "ok", "resource_id": resource_id, "available": new_available}


@app.post("/resources/{resource_id}/return_from_zone")
async def return_resource_from_zone(resource_id: str, req: ReturnZoneResource):
    existing = linkguard_db.get_resource(resource_id)
    if not existing:
        raise HTTPException(status_code=404, detail=t("err.resource_not_found"))

    returned = linkguard_db.return_resource_allocation(
        resource_id,
        assigned_zone=req.assigned_zone,
        quantity=max(1, req.quantity),
    )
    if returned <= 0:
        raise HTTPException(status_code=400, detail="No deployed resource in this zone")

    new_available = min(existing["available"] + returned, existing["total"])
    status = "available" if new_available == existing["total"] else "in_use"
    assigned_to, assigned_zone = _primary_assignment(resource_id)

    linkguard_db.update_resource(resource_id, {
        "available": new_available,
        "status": status,
        "assigned_to": "" if status == "available" else assigned_to,
        "assigned_zone": "" if status == "available" else assigned_zone,
    })
    linkguard_db.log_event(
        "resource_return", "resource-server",
        f"分區資源回收: {resource_id} x{returned} ← {req.assigned_zone}", "info",
    )
    await _broadcast_resource_update()
    return {"status": "ok", "resource_id": resource_id, "available": new_available, "returned": returned}


@app.get("/health")
def health():
    db_ok = False
    try:
        conn = linkguard_db._get_conn()
        conn.execute("SELECT 1")
        conn.close()
        db_ok = True
    except Exception:
        pass
    return health_check_response("resource-server", extras={"db_connected": db_ok})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8006)
