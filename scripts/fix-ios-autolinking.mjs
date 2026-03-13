import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const root = process.cwd()
const rubyPath = join(root, 'nitrogen/generated/ios/NitroGkPhotoBrowser+autolinking.rb')
const swiftPath = join(root, 'nitrogen/generated/ios/NitroGkPhotoBrowserAutolinking.swift')

if (!existsSync(rubyPath)) {
  process.exit(0)
}

let ruby = readFileSync(rubyPath, 'utf8')
ruby = ruby.replace(
  '"nitrogen/generated/shared/**/*.{h,hpp,c,cpp,swift}"',
  '"nitrogen/generated/shared/**/*.{h,hpp,c,cpp}"'
)
ruby = ruby.replace(
  '"nitrogen/generated/ios/**/*.{h,hpp,c,cpp,mm,swift}"',
  '"nitrogen/generated/ios/**/*.{h,hpp,c,cpp,mm}"'
)
ruby = ruby.replace(
  /\s*# Enables C\+\+ <-> Swift interop \(by default it's only ObjC\)\n\s*"SWIFT_OBJC_INTEROP_MODE" => "objcxx",\n/g,
  '\n'
)
writeFileSync(rubyPath, ruby, 'utf8')

if (existsSync(swiftPath)) {
  rmSync(swiftPath)
}
