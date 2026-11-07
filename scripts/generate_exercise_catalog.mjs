#!/usr/bin/env node

// Builds liteweight's bundled catalogue from the MIT-licensed exercise metadata supplied with
// the openGym reference tree. Existing liteweight UUIDs and diagrams are retained for matching
// exercises so historical Core Data relationships remain valid.

import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const sourcePath = path.join(root, 'reference-material/opengym/frontend/src/lib/exercises-data.js')
const outputPath = path.join(root, 'WorkoutDataKit/everkinetic-data/exercises.json')

if (!fs.existsSync(sourcePath)) {
  throw new Error(`Missing openGym reference catalogue: ${sourcePath}`)
}

// Generated openGym entries use negative IDs. Filtering them makes this generator idempotent
// while preserving liteweight's original positive-ID catalogue for UUID and PDF matching.
const legacy = JSON.parse(fs.readFileSync(outputPath, 'utf8'))
  .filter(exercise => exercise.id >= 0)
const source = fs.readFileSync(sourcePath, 'utf8')
const openGym = JSON.parse(source.slice(source.indexOf('['), source.lastIndexOf(']') + 1))

const ignoredWords = new Set(['the', 'with', 'on', 'and', 'using'])
function canonicalName(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/e\.z\./g, 'ez')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(word => word && !ignoredWords.has(word))
    .sort()
    .join(' ')
}

const legacyByName = new Map()
for (const exercise of legacy) {
  for (const name of [exercise.title, ...(exercise.alias || [])]) {
    const key = canonicalName(name)
    const candidates = legacyByName.get(key) || []
    if (!candidates.some(candidate => candidate.uuid === exercise.uuid)) candidates.push(exercise)
    legacyByName.set(key, candidates)
  }
}

const matchedLegacyUuids = new Set()
function uniqueLegacyMatch(exercise) {
  const candidateNames = [exercise.n, `${exercise.eq} ${exercise.n}`, `${exercise.n} ${exercise.eq}`]
  for (const name of candidateNames) {
    const matches = legacyByName.get(canonicalName(name)) || []
    if (matches.length === 1 && !matchedLegacyUuids.has(matches[0].uuid)) return matches[0]
  }
  return null
}

// RFC 4122 version 5 UUIDs keep every openGym exercise stable across generated builds.
const namespace = Buffer.from('6f96f4ec5d984cc3bdf9956e77c36681', 'hex')
function stableUuid(name) {
  const hash = crypto.createHash('sha1').update(namespace).update(name).digest().subarray(0, 16)
  hash[6] = (hash[6] & 0x0f) | 0x50
  hash[8] = (hash[8] & 0x3f) | 0x80
  const hex = hash.toString('hex').toUpperCase()
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

const lowercaseWords = new Set(['and', 'or', 'to', 'with', 'on', 'in'])
function titleCase(value) {
  return String(value)
    .split(' ')
    .map((word, index) => {
      const lower = word.toLowerCase()
      if (lower === 'ez') return 'EZ'
      if (lower === 'sldl') return 'SLDL'
      if (index > 0 && lowercaseWords.has(lower)) return lower
      return word.charAt(0).toUpperCase() + word.slice(1)
    })
    .join(' ')
}

function unique(values) {
  return [...new Set(values.filter(Boolean))]
}

const generated = openGym.map(exercise => {
  const matched = uniqueLegacyMatch(exercise)
  if (matched) matchedLegacyUuids.add(matched.uuid)

  const title = matched?.title || titleCase(exercise.n)
  const aliases = unique([
    ...(matched?.alias || []),
    title.toLowerCase() === exercise.n.toLowerCase() ? null : titleCase(exercise.n),
  ])
  const primary = unique([exercise.tg || exercise.bp])
  const secondary = unique([exercise.mg, ...(exercise.sm || [])])
    .filter(muscle => !primary.includes(muscle))

  return {
    uuid: matched?.uuid || stableUuid(`opengym:${exercise.id}`),
    // Negative IDs cannot collide with legacy Everkinetic IDs or the >=10000 custom range.
    id: matched?.id ?? -(Number.parseInt(exercise.id, 10) + 1),
    title,
    alias: aliases,
    primer: matched?.primer || null,
    primary,
    secondary,
    equipment: unique([exercise.eq]),
    steps: exercise.st || [],
    tips: matched?.tips || [],
    references: matched?.references || [],
    // The app extracts the ExerciseDB media ID and resolves it against the official free
    // V1 CDN at runtime. The third-party binaries are intentionally not copied into liteweight.
    pdf: matched?.pdf || [],
    image: exercise.img || null,
    animation: exercise.gif || null,
  }
})

// Keep unmatched legacy movements so old workout history and liteweight's existing diagrams never
// become unresolved. They remain searchable alongside the broader catalogue.
for (const exercise of legacy) {
  if (!matchedLegacyUuids.has(exercise.uuid)) generated.push(exercise)
}

generated.sort((a, b) => a.title.localeCompare(b.title, 'en', { sensitivity: 'base' }))

const uuidCount = new Set(generated.map(exercise => exercise.uuid)).size
if (uuidCount !== generated.length) {
  throw new Error(`Generated duplicate UUIDs: ${uuidCount} unique for ${generated.length} exercises`)
}

fs.writeFileSync(outputPath, `${JSON.stringify(generated, null, 2)}\n`)
console.log(`Generated ${generated.length} liteweight exercises (${openGym.length} openGym, ${matchedLegacyUuids.size} diagram/history matches, ${legacy.length - matchedLegacyUuids.size} retained legacy).`)
