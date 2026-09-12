-- Mason helpers shared by the LSP and debugger setups: find a binary mason
-- installed, install non-LSP packages (mason-lspconfig only handles servers)
-- and react when an install finishes.

local M = {}

local uv = vim.uv or vim.loop

--- Path of `name` in mason's bin dir (it may not exist yet).
--- @param name string
--- @return string
function M.bin(name)
  return vim.fn.stdpath("data") .. "/mason/bin/" .. name
end

--- Resolve a binary: mason's install dir first, then $PATH, then the bare name.
--- @param name string
--- @return string
function M.cmd(name)
  local bin = M.bin(name)
  if uv.fs_stat(bin) then return bin end
  local on_path = vim.fn.exepath(name)
  return on_path ~= "" and on_path or name
end

--- Install whichever of `pkgs` are missing, in the background.
--- @param pkgs string[] mason package names
function M.ensure(pkgs)
  local ok, registry = pcall(require, "mason-registry")
  if not ok then return end
  registry.refresh(function()
    for _, name in ipairs(pkgs) do
      if registry.has_package(name) and not registry.is_installed(name) then
        registry.get_package(name):install()
      end
    end
  end)
end

--- Run `fn` (scheduled) once `pkg` finishes installing. No-op when it is
--- already installed or unknown to the registry.
--- @param pkg string|nil mason package name
--- @param fn function
function M.on_install(pkg, fn)
  local ok, registry = pcall(require, "mason-registry")
  if not ok or not pkg or not registry.has_package(pkg) or registry.is_installed(pkg) then
    return
  end
  registry.get_package(pkg):once("install:success", vim.schedule_wrap(fn))
end

return M
