import { sum } from './sum.js'

const cases = [
  { input: [], want: 0 },
  { input: [1, 2, 3], want: 6 },
  { input: [-4, 4], want: 0 },
]

for (const { input, want } of cases) {
  const got = sum(input)
  if (got !== want) {
    console.error('sum(' + JSON.stringify(input) + ') = ' + got + ', want ' + want)
    process.exit(1)
  }
}
console.log('ok')
