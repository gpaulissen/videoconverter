import React from "react";
import { Router, Route } from "react-router-dom";
import "./App.css";
import { createBrowserHistory as createHistory } from "history";
import HomePage from "./HomePage";
import { ConversionsStore } from "./store";
import TopBar from "./TopBar";
const conversionsStore = new ConversionsStore();
const history = createHistory();
function App() {
  return (
    <div className="App">
      <TopBar />
      <Router history={history}>
        <Route
          path="/"
          exact
          component={props => (
            <HomePage {...props} conversionsStore={conversionsStore} />
          )}
        />
      </Router>
    </div>
  );
}
export default App;
