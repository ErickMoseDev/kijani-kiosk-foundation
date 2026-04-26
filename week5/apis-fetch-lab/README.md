# Lab: External APIs and Fetching

## Introduction

You’ve just joined the front-end development team of a national safety awareness
organization in the US. Your first assignment is to build a web application that
fetches weather alerts from the National Weather Service API for a specific U.S.
state. The app should dynamically display relevant alert headlines and handle edge
cases like invalid input and network errors.

This lab will strengthen your skills in using the `fetch()` API, working with JSON
data, handling user input, and manipulating the DOM—all essential in modern web
development.

### Note on US State Abbreviations

For this application, you'll be using US state abbreviations. You can find a list of
state abbreviations on the [US Federal Aviation Administration website](https://www.faa.gov/air_traffic/publications/atpubs/cnt_html/appendix_a.html).

## Tools & Resources

- [GitHub Repo](https://github.com/learn-co-curriculum/course-3-module-4-external-apis-and-fetching-lab)
- [fetch()](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API)
- [async/await](https://developer.mozilla.org/en-US/docs/Learn/JavaScript/Asynchronous/Promises)
- [EventTarget.addEventListener()](https://developer.mozilla.org/en-US/docs/Web/API/EventTarget/addEventListener)
- [document.createElement()](https://developer.mozilla.org/en-US/docs/Web/API/Document/createElement)
- [append()](https://developer.mozilla.org/en-US/docs/Web/API/Element/append)
- [JSON](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON)

## Set Up

1. **Fork and Clone the Repository:**
    - Go to the provided GitHub repository link.
    - Fork the repository to your GitHub account.
    - Clone the forked repository to your local machine.
    - Open the project in VSCode.
    - Run `npm install` to install all necessary dependencies.
    - Use `open index.html` or `explorer.exe index.html` to open in browser.
    - Use `npm test` to run the test suite.

## Instructions

1. Fetch Alerts for a Given State

Create a function that takes a U.S. state abbreviation (e.g., "NY") and uses `fetch()`
to request data from the National Weather Service Alerts API:

```javascript
`https://api.weather.gov/alerts/active?area=${STATE_ABBR}`;
```

Replace `STATE_ABBR` with the user’s input value. Handle network and API errors
gracefully.

2. Display the Alerts

When the fetch is successful, show:

- A summary message using the `title` property and number of alerts (under the `features` key) in the data from the API response, like:
    - "Current watches, warnings, and advisories for Minnesota: 11"
- A list of alert headlines, each as its own line or bullet.
    - Each alert is available as an array under `features` and each alert headline is available under `properties.headline` in the array.

3. Clear and Reset the UI

Each time the user fetches new data:

- Clear the input field.
- Update the weather alerts display with fresh data, removing any previous data.

4. Error Handling

When something goes wrong (e.g., empty input, bad state code, or network failure):

- Display the message in the error.
    - from `.catch` this can be accessed using the `message` key:

```javascript
.catch(errorObject => console.log(errorObject.message))
```

- Show the message in a dedicated `<div id="error-message">`.
- Ensure this div is hidden and text is cleared when the next successful request is made.

## BONUS: Additional Features

Explore additional features to further improve the application:

### `loading` Indicator

Add a loading spinner while fetching data to improve user experience:

```js
function showLoadingSpinner() {
	spinnerElement.style.display = 'block';
}

function hideLoadingSpinner() {
	spinnerElement.style.display = 'none';
}
```

### Error Styling

Use CSS classes to style error messages dynamically:

```js
function displayError(message) {
	errorElement.textContent = message;
	errorElement.classList.add('error');
}
```

### Input Validation

Validate that user input is two capital letters before making the request.

## Test and Refine

Use the included Jest tests by running `npm test` to validate:

- The fetch request is made using the input state abbreviation.
- When a successful fetch request is made, the title of the data along with the number
  of alerts is displayed (i.e. 'Current watches, warnings, and advisories for New York:
  7')
- When the 'Get Weather Alerts' button is clicked, the input clears.
- When an unsuccessful request is made the error message is displayed.
- Error messages are cleared and hidden after a successful request.

## Document and Maintain

Once all tests are passing and the app is working as expected, push your working code
to GitHub and submit.

```bash
git commit -am "final solution"
git push origin main
```

### Jenkins - Github weebhooks testing

- push test
