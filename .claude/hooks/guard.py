#!/usr/bin/env python3
"""Nexus AI guard — PreToolUse hook.

Bloquea técnicamente acciones prohibidas aunque el modelo intente ejecutarlas.
Exit 2 = acción bloqueada (Claude Code muestra stderr al modelo). Exit 0 = permitido.
Se ejecuta antes de cada Bash/Edit/Write/Read. Sin dependencias externas.
"""
import json
import os
import re
import sys

# El dueño habilita los despliegues en SU equipo con NEXUS_ALLOW_DEPLOY=1.
# Las ejecuciones programadas en la nube no la definen: ahí sigue bloqueado.
DEPLOY_OK = os.environ.get("NEXUS_ALLOW_DEPLOY") == "1"

PROTECTED_BRANCHES = r"(main|master|production|prod|release)"

# (patrón regex sobre el comando normalizado, motivo)
BASH_RULES = [
    (rf"\bgit\s+push\b.*\s(--force|-f|--force-with-lease)\b", "push forzado prohibido"),
    (rf"\bgit\s+push\b[^;&|]*[\s:/]{PROTECTED_BRANCHES}(\s|$|[;&|])", "push a rama protegida prohibido"),
    (r"\bgit\s+push\b[^;&|]*\s(HEAD|@)(\s|$|[;&|])", "push implícito: indica la rama claude/* explícitamente"),
    (r"\bgit\s+push(\s+-\S+)*(\s+[^\s\-;&|]+)?\s*($|[;&|])", "push implícito: indica la rama claude/* explícitamente"),
    (r"(\.claude/(settings|hooks)|\.github/(workflows|CODEOWNERS)).*", "__WRITE_CHECK__"),
    (r"\bgit\s+(reset\s+--hard|clean\s+-[a-z]*f)", "operación destructiva de git"),
    (r"\bgit\s+branch\s+-D\b", "borrado forzado de ramas"),
    (r"\bgit\s+push\b.*\s--delete\b|\bgit\s+push\b.*\s:\S+", "borrado de ramas remotas"),
    (r"\bgh\s+pr\s+merge\b", "merge de PR prohibido"),
    (r"\bgh\s+pr\s+ready\b", "solo el humano saca el PR de borrador"),
    (r"\bgh\s+(repo\s+delete|release\s+(create|delete)|secret|variable)\b", "operación administrativa de GitHub"),
    (r"\bgh\s+api\b.*(-X|--method)\s*(DELETE|PUT|PATCH)", "escritura directa a la API de GitHub"),
    (r"\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\s+(/|~|\$HOME|\.\s*$|\*|\.\.)", "borrado recursivo peligroso"),
    (r"\b(firebase\s+deploy|vercel\b.*--prod|netlify\s+deploy\b.*--prod|fly\s+deploy|heroku\b|gcloud\s+(app|run|functions)\s+deploy|aws\s+\S+\s+(deploy|delete|terminate)|eas\s+(submit|update)|fastlane)", "__DEPLOY__"),
    (r"\b(npm|pnpm|yarn)\s+run\s+[\w:.-]*(deploy|prod|migrate|seed|clear|reset|drop)\b|\bnetlify\s+deploy\b|\bprisma\s+(migrate\s+(deploy|reset)|db\s+(push|seed))|\bsupabase\s+db\s+(push|reset)", "despliegue o cambio de base de datos prohibido"),
    (r"\b(npm|pnpm|yarn)\s+publish\b|\bflutter\s+pub\s+publish\b|\bdart\s+pub\s+publish\b|\btwine\s+upload\b", "publicación de paquetes prohibida"),
    (r"\b(terraform\s+(apply|destroy)|kubectl|helm\s+(install|upgrade|uninstall)|pulumi\s+up)\b", "cambios de infraestructura prohibidos"),
    (r"\b(psql|mysql|mongosh|mongo|redis-cli)\b.*\b(drop|delete|truncate|update|insert)\b", "escritura en base de datos prohibida"),
    (r"\bfirebase\s+(firestore:delete|database:(set|remove|update|push))", "escritura en datos reales prohibida"),
    (r"(^|[\s;&|])(cat|less|more|head|tail|grep|sed|awk|cp|base64|xxd)\b[^|;&]*(\.env(?!\.(example|sample|template))\b|\.pem\b|\.key\b|id_rsa|serviceAccount[^ ]*\.json|credentials\.json)", "acceso a secretos prohibido"),
    (r"\b(printenv|env)\b\s*($|[|;&])", "volcado de variables de entorno prohibido"),
    (r"\bcurl\b.*\|\s*(sh|bash)\b|\bwget\b.*\|\s*(sh|bash)\b", "ejecución de scripts remotos prohibida"),
]

WRITE_OPS = re.compile(r"((?<![0-9])>(?!&)|\bsed\s+-i|\btee\b|\bmv\b|\bcp\b|\brm\b|\bchmod\b|\btruncate\b|\bpython3?\b|\bperl\b|\bnode\b|\bln\b|\bgit\s+(rm|mv|checkout\s+\S+\s+--))")

SECRET_PATH = re.compile(
    r"(^|/)(\.env(\..*)?|.*\.pem|.*\.key|id_rsa.*|serviceAccount.*\.json|credentials\.json|google-services\.json|GoogleService-Info\.plist|key\.properties|.*\.keystore|.*\.jks)$"
)
PROTECTED_EDIT = re.compile(r"(^|/)(\.github/workflows/|\.claude/settings(\.local)?\.json$|\.claude/hooks/|\.github/CODEOWNERS$)")


def block(reason: str) -> None:
    print(f"BLOQUEADO por Nexus guard: {reason}. Si es necesario, regístralo como PROPUESTA en docs/DECISIONS.md y solicita aprobación humana.", file=sys.stderr)
    sys.exit(2)


def check_bash(cmd: str) -> None:
    norm = " ".join(cmd.split())
    for pattern, reason in BASH_RULES:
        if re.search(pattern, norm, flags=re.IGNORECASE):
            if reason == "__WRITE_CHECK__":
                # Lectura de controles permitida; cualquier escritura no.
                if WRITE_OPS.search(norm):
                    block("modificar controles de seguridad/CI requiere aprobación humana")
                continue
            if reason == "__DEPLOY__":
                # Permitido solo si el dueño lo habilitó en su equipo.
                if DEPLOY_OK:
                    continue
                block("despliegue a producción prohibido (habilítalo con NEXUS_ALLOW_DEPLOY=1)")
            block(reason)


def check_path(tool: str, path: str) -> None:
    if not path:
        return
    p = path.replace("\\", "/")
    if SECRET_PATH.search(p) and not p.endswith((".example", ".sample", ".template")):
        block(f"{tool} sobre archivo de secretos ({path})")
    if tool != "Read" and PROTECTED_EDIT.search(p):
        block(f"modificar controles de seguridad/CI ({path}) requiere aprobación humana")


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        block("entrada de hook ilegible (fail-closed)")
    tool = data.get("tool_name", "")
    tin = data.get("tool_input", {}) or {}
    if tool == "Bash":
        check_bash(tin.get("command", ""))
    elif tool in ("Edit", "Write", "MultiEdit", "NotebookEdit", "Read"):
        check_path(tool, tin.get("file_path") or tin.get("notebook_path") or "")
    sys.exit(0)


if __name__ == "__main__":
    main()